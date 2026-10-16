// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {IMDenzaDistributor} from "../src/IMDenzaDistributor.sol";
import {MockERC20, RejectingReceiver, ReentrantClaimer} from "./mocks/Mocks.sol";

contract IMDenzaDistributorTest is BaseTest {
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

    function test_distributeRevertsWithoutTokensOrValue() public {
        vm.deal(address(dist), 1 ether);
        vm.expectRevert(IMDenzaDistributor.NoTokensMinted.selector);
        dist.distribute(ETH);
        _claimImd(alice);
        dist.distribute(ETH);
        vm.expectRevert(IMDenzaDistributor.NothingToDistribute.selector);
        dist.distribute(ETH);
    }

    function test_ethRoyaltiesSplitEquallyAndLaterMintsDoNotShareEarlierValue() public {
        uint256 a = _claimImd(alice);
        uint256 b = _claimImd(bob);
        (bool ok,) = address(dist).call{value: 2 ether}("");
        assertTrue(ok);
        dist.distribute(ETH);
        assertEq(dist.pending(ETH, a), 1 ether);
        assertEq(dist.pending(ETH, b), 1 ether);

        uint256 c = _claimImd(carol);
        assertEq(dist.pending(ETH, c), 0);

        (ok,) = address(dist).call{value: 3 ether}("");
        assertTrue(ok);
        dist.distribute(ETH);
        assertEq(dist.pending(ETH, a), 2 ether);
        assertEq(dist.pending(ETH, b), 2 ether);
        assertEq(dist.pending(ETH, c), 1 ether);

        uint256 before = alice.balance;
        vm.prank(bob); // anyone may trigger; payment goes to the owner
        uint256 paid = dist.claim(ETH, _ids(a));
        assertEq(paid, 2 ether);
        assertEq(alice.balance - before, 2 ether);
        assertEq(dist.pending(ETH, a), 0);

        vm.expectRevert(IMDenzaDistributor.NothingToClaim.selector);
        dist.claim(ETH, _ids(a));

        // a third distribution after the claim accrues again
        (ok,) = address(dist).call{value: 3 ether}("");
        assertTrue(ok);
        dist.distribute(ETH);
        assertEq(dist.pending(ETH, a), 1 ether);
        assertEq(dist.pending(ETH, b), 3 ether);
    }

    function test_unclaimedValueTravelsWithTheToken() public {
        uint256 a = _claimImd(alice);
        vm.deal(address(dist), 1 ether);
        dist.distribute(ETH);
        vm.prank(alice);
        nft.transferFrom(alice, bob, a);
        uint256 before = bob.balance;
        dist.claim(ETH, _ids(a));
        assertEq(bob.balance - before, 1 ether);
    }

    function test_claimRequiresSingleOwnerAndNonEmptyList() public {
        uint256 a = _claimImd(alice);
        uint256 b = _claimImd(bob);
        vm.deal(address(dist), 2 ether);
        dist.distribute(ETH);
        vm.expectRevert(IMDenzaDistributor.EmptyClaim.selector);
        dist.claim(ETH, new uint256[](0));
        vm.expectRevert(IMDenzaDistributor.NotOwnerOfAll.selector);
        dist.claim(ETH, _ids(a, b));
        vm.prank(bob);
        nft.transferFrom(bob, alice, b);
        assertEq(dist.claim(ETH, _ids(a, b)), 2 ether);
    }

    function test_erc20RoyaltiesAndMintProceeds() public {
        MockERC20 weth = new MockERC20("WETH", "WETH", 18);
        uint256 a = _claimImd(alice);
        uint256 b = _publicMint(bob); // 90% of the price is distributed to a and b at mint
        uint256 price = nft.mintPrice(address(imd));
        uint256 share = (price - price / 10) / 2;
        assertEq(dist.pending(address(imd), a), share);
        assertEq(dist.pending(address(imd), b), share);

        weth.mint(address(dist), 4 ether);
        dist.distribute(address(weth));
        assertEq(dist.pending(address(weth), a), 2 ether);
        dist.claim(address(weth), _ids(b));
        assertEq(weth.balanceOf(bob), 2 ether);
        uint256 before = imd.balanceOf(alice);
        dist.claim(address(imd), _ids(a));
        assertEq(imd.balanceOf(alice) - before, share);
        assertEq(dist.reserved(address(imd)), share);
    }

    function test_rejectingReceiverOnlyBlocksItsOwnClaim() public {
        RejectingReceiver r = new RejectingReceiver();
        uint256 a = _claimImd(alice);
        uint256 b = _claimImd(bob);
        vm.prank(alice);
        nft.transferFrom(alice, address(r), a);
        vm.deal(address(dist), 2 ether);
        dist.distribute(ETH);
        vm.expectRevert(IMDenzaDistributor.EthTransferFailed.selector);
        dist.claim(ETH, _ids(a));
        assertEq(dist.claim(ETH, _ids(b)), 1 ether);
    }

    function test_reentrantClaimIsRejected() public {
        ReentrantClaimer r = new ReentrantClaimer();
        uint256 a = _claimImd(alice);
        vm.prank(alice);
        nft.transferFrom(alice, address(r), a);
        vm.deal(address(dist), 1 ether);
        dist.distribute(ETH);
        r.arm(address(dist), ETH, _ids(a));
        dist.claim(ETH, _ids(a));
        assertTrue(r.reentered());
        assertTrue(r.reentryFailed());
        assertEq(address(r).balance, 1 ether);
        assertEq(address(dist).balance, 0);
    }

    function test_pendingIsZeroForUnknownTokens() public {
        _claimImd(alice);
        vm.deal(address(dist), 1 ether);
        dist.distribute(ETH);
        assertEq(dist.pending(ETH, 0), 0);
        assertEq(dist.pending(ETH, 2), 0);
        assertEq(dist.checkpointCount(ETH), 1);
        IMDenzaDistributor.Checkpoint memory cp = dist.checkpointAt(ETH, 0);
        assertEq(cp.minted, 1);
        assertEq(cp.acc, 1 ether * dist.PRECISION());
    }

    /// @dev Conservation: after random distributions interleaved with mints, every token can claim,
    ///      the sum of claims never exceeds what was received, and the shortfall is only rounding dust.
    function testFuzz_conservation(uint8 holders, uint64[4] memory amounts) public {
        holders = uint8(bound(holders, 1, 6));
        address[] memory wallets = new address[](holders);
        uint256 total;
        for (uint256 i; i < holders; ++i) {
            wallets[i] = makeAddr(string(abi.encodePacked("h", i)));
            _claimImd(wallets[i]);
            uint256 amt = bound(amounts[i % 4], 1, 100 ether);
            vm.deal(address(dist), address(dist).balance + amt);
            dist.distribute(ETH);
            total += amt;
        }
        uint256 claimed;
        for (uint256 i; i < holders; ++i) {
            uint256[] memory ids = new uint256[](1);
            ids[0] = i + 1;
            if (dist.pending(ETH, i + 1) == 0) continue;
            claimed += dist.claim(ETH, ids);
        }
        assertLe(claimed, total);
        assertLe(total - claimed, uint256(holders) * holders);
        assertEq(address(dist).balance, total - claimed);
    }
}
