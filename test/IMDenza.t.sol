// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IMDenza} from "../src/IMDenza.sol";
import {IMDenzaRenderer} from "../src/IMDenzaRenderer.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ICreatorToken} from "@limitbreak/creator-token-standards/interfaces/ICreatorToken.sol";
import {MockERC20} from "./mocks/Mocks.sol";

contract IMDenzaTest is BaseTest {
    using stdStorage for StdStorage;

    // ------------------------------------------------------------ deployment

    function test_deploymentWiring() public view {
        assertEq(nft.name(), "IMDenza");
        assertEq(nft.symbol(), "IMDENZA");
        assertEq(nft.MAX_SUPPLY(), 3333);
        assertEq(address(dist.nft()), address(nft));
        assertEq(address(nft.renderer()), address(renderer));
        assertEq(address(nft.swarm()), address(swarm));
        assertEq(nft.configurator(), CONFIGURATOR);
        assertEq(nft.identityMdCollection(), address(0));
        assertEq(nft.getTransferValidator(), VALIDATOR);
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(ICreatorToken).interfaceId));
    }

    function test_noOwnerPowers() public {
        vm.expectRevert(IMDenza.NoOwner.selector);
        nft.setTransferValidator(address(0));
        vm.prank(CONFIGURATOR);
        vm.expectRevert(IMDenza.NoOwner.selector);
        nft.setAutomaticApprovalOfTransfersFromValidator(true);
    }

    function test_constructorRejectsZeroAddresses() public {
        vm.expectRevert(IMDenza.ZeroAddress.selector);
        new IMDenza(address(0), address(renderer), address(swarm));
        vm.expectRevert(IMDenza.ZeroAddress.selector);
        new IMDenza(CONFIGURATOR, address(0), address(swarm));
        vm.expectRevert(IMDenza.ZeroAddress.selector);
        new IMDenza(CONFIGURATOR, address(renderer), address(0));
    }

    function test_constructorsSucceedOnAnEmptyChain() public {
        // The launch rehearses constructors where no other contract exists.
        vm.etch(VALIDATOR, "");
        IMDenza fresh = new IMDenza(CONFIGURATOR, address(renderer), address(swarm));
        assertEq(address(fresh.distributor().nft()), address(fresh));
        assertEq(fresh.getTransferValidator(), VALIDATOR);
    }

    // ------------------------------------------------------------ configuration

    function test_identityCollectionIsOneShotAndConfiguratorOnly() public {
        vm.prank(alice);
        vm.expectRevert(IMDenza.NotConfigurator.selector);
        nft.setIdentityMdCollection(address(identity));

        vm.prank(CONFIGURATOR);
        vm.expectRevert(IMDenza.ZeroAddress.selector);
        nft.setIdentityMdCollection(address(0));

        vm.prank(CONFIGURATOR);
        vm.expectEmit();
        emit IMDenza.IdentityMdCollectionSet(address(identity));
        nft.setIdentityMdCollection(address(identity));
        assertEq(nft.identityMdCollection(), address(identity));

        vm.prank(CONFIGURATOR);
        vm.expectRevert(IMDenza.AlreadyConfigured.selector);
        nft.setIdentityMdCollection(address(this));
    }

    // ------------------------------------------------------------ identity claim

    function test_identityClaimRevertsUntilConfigured() public {
        identity.mint(alice, 7);
        vm.prank(alice);
        vm.expectRevert(IMDenza.NotConfigured.selector);
        nft.claimWithIdentityMd(7);
    }

    function test_identityClaimSuccessAndLimits() public {
        vm.prank(CONFIGURATOR);
        nft.setIdentityMdCollection(address(identity));
        identity.mint(alice, 7);
        identity.mint(alice, 8);
        identity.mint(bob, 9);

        vm.prank(alice);
        uint256 id = nft.claimWithIdentityMd(7);
        assertEq(id, 1);
        assertEq(nft.ownerOf(1), alice);
        assertTrue(nft.identityTokenUsed(7));

        // one per wallet, even with a second NFT
        vm.prank(alice);
        vm.expectRevert(IMDenza.AlreadyClaimed.selector);
        nft.claimWithIdentityMd(8);

        // same NFT passed to another wallet cannot be reused
        vm.prank(alice);
        identity.transferFrom(alice, bob, 7);
        vm.prank(bob);
        vm.expectRevert(IMDenza.TokenAlreadyUsed.selector);
        nft.claimWithIdentityMd(7);

        // not the owner
        vm.prank(carol);
        vm.expectRevert(IMDenza.NotTokenOwner.selector);
        nft.claimWithIdentityMd(9);

        vm.prank(bob);
        assertEq(nft.claimWithIdentityMd(9), 2);
    }

    // ------------------------------------------------------------ IMD claim

    function test_imdClaimRequiresMoreThan25() public {
        _giveImd(alice, 25 ether);
        vm.prank(alice);
        vm.expectRevert(IMDenza.InsufficientImd.selector);
        nft.claimWithImd();
        assertFalse(nft.holdsImd(alice));

        _giveImd(alice, 1);
        assertTrue(nft.holdsImd(alice));
        vm.prank(alice);
        assertEq(nft.claimWithImd(), 1);

        vm.prank(alice);
        vm.expectRevert(IMDenza.AlreadyClaimed.selector);
        nft.claimWithImd();
    }

    function test_imdClaimCountsSecondTokenWhenItHasCode() public {
        vm.etch(nft.IMD_TOKEN_B(), address(new MockERC20("IMD2", "IMD2", 6)).code);
        MockERC20(nft.IMD_TOKEN_B()).mint(bob, 25_000_001);
        assertTrue(nft.holdsImd(bob));
        vm.prank(bob);
        assertEq(nft.claimWithImd(), 1);
    }

    function test_failedClaimDoesNotConsumeTheWalletsClaim() public {
        vm.prank(alice);
        vm.expectRevert(IMDenza.InsufficientImd.selector);
        nft.claimWithImd();
        assertEq(nft.claimFlags(alice), 0);
    }

    // ------------------------------------------------------------ Fidenza claim

    function test_fidenzaClaimChecksProjectOwnershipAndReuse() public {
        artBlocks.mint(alice, 78_000_123);
        artBlocks.mint(alice, 77_000_001); // another Art Blocks project

        vm.prank(alice);
        vm.expectRevert(IMDenza.NotFidenza.selector);
        nft.claimWithFidenza(77_000_001);

        vm.prank(bob);
        vm.expectRevert(IMDenza.NotTokenOwner.selector);
        nft.claimWithFidenza(78_000_123);

        vm.prank(alice);
        assertEq(nft.claimWithFidenza(78_000_123), 1);
        assertTrue(nft.fidenzaTokenUsed(78_000_123));

        vm.prank(alice);
        artBlocks.transferFrom(alice, bob, 78_000_123);
        vm.prank(bob);
        vm.expectRevert(IMDenza.TokenAlreadyUsed.selector);
        nft.claimWithFidenza(78_000_123);
    }

    function test_eachRouteIsIndependentPerWallet() public {
        vm.prank(CONFIGURATOR);
        nft.setIdentityMdCollection(address(identity));
        identity.mint(alice, 1);
        artBlocks.mint(alice, 78_000_000);
        _giveImd(alice, 100 ether);
        vm.startPrank(alice);
        nft.claimWithIdentityMd(1);
        nft.claimWithImd();
        nft.claimWithFidenza(78_000_000);
        vm.stopPrank();
        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.claimFlags(alice), 7);
    }

    // ------------------------------------------------------------ public mint

    function test_mintPriceFollowsTokenDecimals() public {
        assertEq(nft.mintPrice(address(imd)), 0.069 ether);
        vm.etch(nft.IMD_TOKEN_B(), address(new MockERC20("IMD2", "IMD2", 6)).code);
        assertEq(nft.mintPrice(nft.IMD_TOKEN_B()), 69_000);
        vm.expectRevert(IMDenza.UnsupportedPaymentToken.selector);
        nft.mintPrice(address(this));
    }

    function test_publicMintSplitsProceeds90_10() public {
        uint256 price = nft.mintPrice(address(imd));
        uint256 id = _publicMint(alice);
        assertEq(id, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(imd.balanceOf(nft.TREASURY()), price / 10);
        assertEq(imd.balanceOf(address(dist)), price - price / 10);
        assertEq(imd.balanceOf(address(nft)), 0);
        // the minter's own token shares in the distribution made at its mint
        assertEq(dist.pending(address(imd), 1), price - price / 10);
    }

    function test_publicMintRevertsWithoutApprovalOrFunds() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.mint(address(imd));

        vm.prank(alice);
        vm.expectRevert(IMDenza.UnsupportedPaymentToken.selector);
        nft.mint(address(this));

        // token B has no code: refused before any transfer
        address tokenB = nft.IMD_TOKEN_B();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDenza.NoCode.selector, tokenB));
        nft.mint(tokenB);
        assertEq(nft.totalMinted(), 0);
    }

    function test_soldOutStopsEveryRoute() public {
        // place the counter at the cap without minting 3333 pieces
        uint256 slot = stdstore.target(address(nft)).sig("totalMinted()").find();
        vm.store(address(nft), bytes32(slot), bytes32(uint256(3333)));
        assertEq(nft.totalMinted(), 3333);

        _giveImd(alice, 100 ether);
        vm.prank(alice);
        vm.expectRevert(IMDenza.SoldOut.selector);
        nft.claimWithImd();

        uint256 price = nft.mintPrice(address(imd));
        vm.startPrank(alice);
        imd.approve(address(nft), price);
        vm.expectRevert(IMDenza.SoldOut.selector);
        nft.mint(address(imd));
        vm.stopPrank();
    }

    function test_lastPieceMintsThenSoldOut() public {
        uint256 slot = stdstore.target(address(nft)).sig("totalMinted()").find();
        vm.store(address(nft), bytes32(slot), bytes32(uint256(3332)));
        assertEq(_claimImd(alice), 3333);
        _giveImd(bob, 26 ether);
        vm.prank(bob);
        vm.expectRevert(IMDenza.SoldOut.selector);
        nft.claimWithImd();
    }

    // ------------------------------------------------------------ uniqueness

    function test_tokensMintedInSameBlockAreUnique() public {
        uint256 a = _claimImd(alice);
        uint256 b = _claimImd(bob);
        uint256 c = _publicMint(alice);
        assertTrue(nft.seedOf(a) != nft.seedOf(b));
        assertTrue(nft.seedOf(b) != nft.seedOf(c));
        assertTrue(nft.seedOf(a) != nft.seedOf(c));
        IMDenza.TokenData memory da = nft.tokenData(a);
        IMDenza.TokenData memory dc = nft.tokenData(c);
        assertTrue(da.tokenHash != dc.tokenHash);
        assertTrue(nft.tokenHashUsed(da.tokenHash));
        assertTrue(nft.seedUsed(nft.seedOf(a)));
        assertEq(da.mintBlock, uint32(block.number));
    }

    function test_reusedTokenHashIsRehashed() public {
        // Pre-mark the hash the next mint would produce as used; the mint must pick another.
        uint256 tokenId = 1;
        bytes32 h = keccak256(
            abi.encodePacked(
                tokenId, blockhash(block.number - 1), block.prevrandao, alice, block.number, block.timestamp
            )
        );
        uint256 slot = stdstore.target(address(nft)).sig("tokenHashUsed(bytes32)").with_key(h).find();
        vm.store(address(nft), bytes32(slot), bytes32(uint256(1)));
        _claimImd(alice);
        assertEq(nft.tokenData(1).tokenHash, keccak256(abi.encodePacked(h)));
    }

    function test_swarmSnapshotIsFrozenAtMint() public {
        uint256 a = _claimImd(alice);
        swarm.recordJob(bytes32("j1"), 0, 2, 1, uint40(block.timestamp));
        swarm.recordJob(bytes32("j2"), 3, 5, 1, uint40(block.timestamp));
        uint256 b = _claimImd(bob);
        IMDenza.TokenData memory da = nft.tokenData(a);
        IMDenza.TokenData memory db = nft.tokenData(b);
        assertEq(da.swarmJobIndex, 0);
        assertEq(db.swarmJobIndex, 2);
        assertEq(da.swarmEntropy, bytes32(0));
        assertEq(db.swarmEntropy, swarm.entropy());
        assertEq(db.typeProfile, (uint64(1) << 24) | 1);
        swarm.recordJob(bytes32("j3"), 1, 1, 1, uint40(block.timestamp));
        assertEq(nft.tokenData(b).swarmEntropy, db.swarmEntropy);
    }

    // ------------------------------------------------------------ royalties & policy

    function test_royaltyInfo() public view {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 10 ether);
        assertEq(receiver, address(dist));
        assertEq(amount, 0.69 ether);
    }

    function test_policyAppliedOnFirstMintWithFixedParameters() public {
        assertFalse(nft.transferPolicyApplied());
        _claimImd(alice);
        assertTrue(nft.transferPolicyApplied());
        (uint8 level, bool a, bool b, bool c, uint120 listId, uint16 tokenType, uint256 calls) =
            validator.policies(address(nft));
        assertEq(level, 3);
        assertFalse(a);
        assertFalse(b);
        assertFalse(c);
        assertEq(listId, 0);
        assertEq(tokenType, 721);
        assertEq(calls, 1);
        // idempotent, permissionless re-application
        vm.prank(bob);
        nft.applyTransferPolicy();
        (,,,,,, calls) = validator.policies(address(nft));
        assertEq(calls, 2);
    }

    function test_mintProceedsWhenValidatorRejectsPolicyAndExplicitCallReverts() public {
        validator.setRevertOnPolicy(true);
        _claimImd(alice);
        assertFalse(nft.transferPolicyApplied());
        vm.expectRevert("policy disabled");
        nft.applyTransferPolicy();
        validator.setRevertOnPolicy(false);
        nft.applyTransferPolicy();
        assertTrue(nft.transferPolicyApplied());
    }

    function test_applyPolicyRevertsWhenValidatorHasNoCode() public {
        vm.etch(VALIDATOR, "");
        vm.expectRevert(abi.encodeWithSelector(IMDenza.NoCode.selector, VALIDATOR));
        nft.applyTransferPolicy();
        // minting still works; policy stays unapplied
        _claimImd(alice);
        assertFalse(nft.transferPolicyApplied());
    }

    function test_transfersGoThroughValidator() public {
        uint256 id = _claimImd(alice);
        vm.prank(alice);
        nft.transferFrom(alice, bob, id);
        assertEq(nft.ownerOf(id), bob);

        address marketplace = makeAddr("marketplace");
        vm.prank(bob);
        nft.setApprovalForAll(marketplace, true);
        validator.setBlockedOperator(marketplace, true);
        vm.prank(marketplace);
        vm.expectRevert("operator blocked");
        nft.transferFrom(bob, carol, id);

        validator.setBlockedOperator(marketplace, false);
        vm.prank(marketplace);
        nft.transferFrom(bob, carol, id);
        assertEq(nft.ownerOf(id), carol);
    }

    // ------------------------------------------------------------ metadata

    function test_viewsRevertForNonexistentToken() public {
        vm.expectRevert(IMDenza.NonexistentToken.selector);
        nft.tokenURI(1);
        vm.expectRevert(IMDenza.NonexistentToken.selector);
        nft.traits(1);
        vm.expectRevert(IMDenza.NonexistentToken.selector);
        nft.tokenData(1);
    }

    function test_tokenUriAndTraits() public {
        for (uint256 i; i < 3; ++i) {
            swarm.recordJob(bytes32(i + 1), uint8(i), 2, 1, uint40(block.timestamp));
        }
        uint256 id = _claimImd(alice);
        string memory uri = nft.tokenURI(id);
        assertEq(_prefix(uri, 29), "data:application/json;base64,");
        string memory svg = nft.svg(id);
        assertEq(_prefix(svg, 4), "<svg");
        assertTrue(bytes(svg).length > 2000);
        IMDenzaRenderer.Traits memory t = nft.traits(id);
        assertEq(t.seed, nft.seedOf(id));
        assertEq(t.jobsTo, 3);
        assertEq(t.traces, 3);
        assertEq(t.accents, 3);
        assertTrue(t.scale <= 3 && t.turbulence <= 3 && t.density <= 2 && t.palette <= 7);
        assertEq(t.pulse, swarm.pulse());
        assertEq(t.pulseInfluence, 30);
    }

    function _prefix(string memory s, uint256 n) internal pure returns (string memory out) {
        bytes memory b = bytes(s);
        bytes memory o = new bytes(n);
        for (uint256 i; i < n; ++i) {
            o[i] = b[i];
        }
        out = string(o);
    }
}
