// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {IMDenza} from "../src/IMDenza.sol";
import {IMDenzaRenderer} from "../src/IMDenzaRenderer.sol";
import {IMDenzaDistributor} from "../src/IMDenzaDistributor.sol";
import {MockERC20, LazyERC20, MintOnPayout} from "./mocks/Mocks.sol";

/// @dev Regression tests for the independent review: density range, distributor rounding and
///      attribution timing, configurator validation, IMD token decimals, same-block ledger rerolls.
contract HardeningTest is BaseTest {
    address constant ETH = address(0);

    function _ids(uint256 a) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = a;
    }

    function _ids(uint256 a, uint256 b) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;
    }

    function _send(uint256 amount) internal {
        (bool ok,) = address(dist).call{value: amount}("");
        assertTrue(ok);
    }

    // ------------------------------------------------------------ renderer

    /// @dev Density is one of three buckets for every seed and every swarm entropy.
    function testFuzz_densityHasThreeBuckets(bytes32 tokenHash, bytes32 entropy, uint16 tokenId) public view {
        IMDenzaRenderer.Piece memory p = IMDenzaRenderer.Piece({
            tokenId: uint256(tokenId) + 1, tokenHash: tokenHash, swarmEntropy: entropy, swarmJobIndex: 0, typeProfile: 0
        });
        IMDenzaRenderer.Traits memory t = renderer.traits(p);
        assertLe(t.density, 2);
        assertLe(t.scale, 3);
        assertLe(t.turbulence, 3);
    }

    /// @dev The maximal density input (seed byte 99, entropy bias +10) is Dense and renders.
    function test_maxDensityInputRenders() public view {
        bytes32 entropy = bytes32(uint256(20) << 232); // entropy byte 2 = 20 -> +10
        IMDenzaRenderer.Piece memory p;
        p.tokenId = 1;
        p.swarmEntropy = entropy;
        for (uint256 i;; ++i) {
            p.tokenHash = keccak256(abi.encodePacked("dense", i));
            if (uint8(renderer.seedOf(p)[2]) % 100 >= 91) break;
        }
        assertEq(renderer.traits(p).density, 2);
        assertGt(bytes(renderer.tokenURI(p)).length, 0);
    }

    // ------------------------------------------------------------ distributor rounding

    function test_oddDistributionsNeverOverPromise() public {
        _claimImd(alice);
        _claimImd(bob);
        _claimImd(carol);
        for (uint256 i; i < 3; ++i) {
            _send(5);
            dist.distribute(ETH);
        }
        uint256 owed;
        for (uint256 id = 1; id <= 3; ++id) {
            owed += dist.pending(ETH, id);
        }
        assertLe(owed, dist.reserved(ETH));
        assertLe(dist.reserved(ETH), address(dist).balance);
        for (uint256 id = 1; id <= 3; ++id) {
            dist.claim(ETH, _ids(id));
        }
        assertEq(address(dist).balance, 15 - owed);
    }

    function test_replayedDistributeIsANoOp() public {
        _claimImd(alice);
        _claimImd(bob);
        _claimImd(carol);
        _send(5);
        assertEq(dist.distribute(ETH), 5); // 3 x 1.666.. wei credited, 5 wei reserved
        uint256 acc = dist.accPerToken(ETH);
        for (uint256 i; i < 7; ++i) {
            assertEq(dist.distribute(ETH), 0);
        }
        assertEq(dist.accPerToken(ETH), acc);
        assertEq(dist.reserved(ETH), 5);
    }

    function test_fractionalCreditStaysClaimable() public {
        _claimImd(alice);
        _claimImd(bob);
        _send(3);
        dist.distribute(ETH); // 1.5 wei each
        assertEq(dist.claim(ETH, _ids(1)), 1);
        assertEq(dist.pending(ETH, 1), 0);
        _send(3);
        dist.distribute(ETH); // token 1 now holds 0.5 + 1.5 wei
        assertEq(dist.pending(ETH, 1), 2);
        assertEq(dist.claim(ETH, _ids(1)), 2);
        // token 2 earned 3 wei in total and gets all of it
        assertEq(dist.claim(ETH, _ids(2)), 3);
        assertEq(dist.reserved(ETH), 0);
        assertEq(address(dist).balance, 0);
    }

    function test_batchClaimPaysTheSumOfPending() public {
        _claimImd(alice);
        _claimImd(bob);
        vm.prank(bob);
        nft.transferFrom(bob, alice, 2);
        _send(3);
        dist.distribute(ETH);
        uint256 views = dist.pending(ETH, 1) + dist.pending(ETH, 2);
        assertEq(dist.claim(ETH, _ids(1, 2)), views);
    }

    // ------------------------------------------------------------ attribution timing

    function test_valueArrivedBeforeAMintIsNotSharedWithIt() public {
        _claimImd(alice);
        _send(10 ether); // royalties while only token 1 exists, nobody calls distribute
        MockERC20 weth = MockERC20(nft.WETH());
        vm.etch(address(weth), address(new MockERC20("WETH", "WETH", 18)).code);
        weth.mint(address(dist), 4 ether);

        uint256 b = _publicMint(bob);
        dist.distribute(ETH); // nothing left to share with token 2
        dist.distribute(address(weth));
        assertEq(dist.pending(ETH, 1), 10 ether);
        assertEq(dist.pending(ETH, b), 0);
        assertEq(dist.pending(address(weth), 1), 4 ether);
        assertEq(dist.pending(address(weth), b), 0);
    }

    function test_syncIsPermissionlessAndSkipsUnreadableAssets() public {
        address[] memory assets = new address[](3);
        assets[0] = ETH;
        assets[1] = address(renderer); // has code, no balanceOf
        assets[2] = makeAddr("no-code");
        _send(1 ether);
        dist.sync(assets); // nothing minted: no-op
        assertEq(dist.reserved(ETH), 0);
        _claimImd(alice); // the mint itself syncs before token 1 exists: still nothing
        assertEq(dist.reserved(ETH), 0);
        vm.prank(bob);
        dist.sync(assets);
        assertEq(dist.pending(ETH, 1), 1 ether);
    }

    function test_mintFromInsideAPayoutIsRefused() public {
        MintOnPayout m = new MintOnPayout();
        m.setNft(address(nft));
        _giveImd(address(m), 26 ether);
        uint256 a = _claimImd(alice);
        vm.prank(alice);
        nft.transferFrom(alice, address(m), a);
        _send(1 ether);
        dist.distribute(ETH);
        dist.claim(ETH, _ids(a));
        assertTrue(m.attempted());
        assertTrue(m.mintFailed());
        assertEq(nft.totalMinted(), 1);
        assertEq(address(m).balance, 1 ether);
    }

    // ------------------------------------------------------------ configurator

    function test_identityCollectionMustBeAnErc721ElsewhereThanHere() public {
        address artBlocksCore = nft.ART_BLOCKS();
        vm.startPrank(CONFIGURATOR);
        vm.expectRevert(IMDenza.InvalidCollection.selector);
        nft.setIdentityMdCollection(address(nft));
        vm.expectRevert(IMDenza.InvalidCollection.selector);
        nft.setIdentityMdCollection(address(dist));
        vm.expectRevert(IMDenza.InvalidCollection.selector);
        nft.setIdentityMdCollection(artBlocksCore);
        address dead = 0x000000000000000000000000000000000000dEaD;
        vm.expectRevert(abi.encodeWithSelector(IMDenza.NoCode.selector, dead));
        nft.setIdentityMdCollection(dead);
        vm.expectRevert(abi.encodeWithSelector(IMDenza.NotErc721.selector, address(renderer)));
        nft.setIdentityMdCollection(address(renderer));
        // A rejected value leaves the setter usable.
        nft.setIdentityMdCollection(address(identity));
        vm.stopPrank();
        assertEq(nft.identityMdCollection(), address(identity));
    }

    // ------------------------------------------------------------ IMD token decimals

    function test_tokenBWithTooFewDecimalsCannotBeUsedToPay() public {
        address tokenB = nft.IMD_TOKEN_B();
        vm.etch(tokenB, address(new MockERC20("IMD", "IMD", 2)).code);
        vm.expectRevert(abi.encodeWithSelector(IMDenza.UnsupportedDecimals.selector, tokenB));
        nft.mintPrice(tokenB);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDenza.UnsupportedDecimals.selector, tokenB));
        nft.mint(tokenB);
    }

    function test_tokenBWithHugeDecimalsDoesNotBlockImdClaims() public {
        address tokenB = nft.IMD_TOKEN_B();
        vm.etch(tokenB, address(new MockERC20("IMD", "IMD", 78)).code);
        assertFalse(nft.holdsImd(bob));
        vm.prank(bob);
        vm.expectRevert(IMDenza.InsufficientImd.selector);
        nft.claimWithImd();
        _claimImd(alice); // token A still qualifies
        vm.expectRevert(abi.encodeWithSelector(IMDenza.UnsupportedDecimals.selector, tokenB));
        nft.mintPrice(tokenB);
    }

    function test_paymentThatDoesNotArriveIsRefused() public {
        address tokenB = nft.IMD_TOKEN_B();
        vm.etch(tokenB, address(new LazyERC20()).code);
        uint256 price = nft.mintPrice(tokenB);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDenza.UnderPaid.selector, 0, price));
        nft.mint(tokenB);
        assertEq(nft.totalMinted(), 0);
    }

    // ------------------------------------------------------------ same-block ledger rerolls

    /// @dev Records made in the mint's own block cannot move its composition.
    function test_sameBlockRecordsDoNotChangeTheSeed() public {
        swarm.recordJob(bytes32("early"), 0, 1, 1, uint40(block.timestamp));
        vm.roll(block.number + 1);
        (bytes32 settled,,) = swarm.snapshot();
        swarm.recordJob(bytes32("reroll-1"), 7, 1, 0, uint40(block.timestamp));
        swarm.recordJob(bytes32("reroll-2"), 7, 1, 0, uint40(block.timestamp));
        uint256 id = _claimImd(alice);
        assertEq(nft.tokenData(id).swarmEntropy, settled);
        assertEq(nft.tokenData(id).swarmJobIndex, 1);
    }
}
