// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "../Base.t.sol";
import {IMDenzaDistributor} from "../../src/IMDenzaDistributor.sol";
import {MockERC20} from "../mocks/Mocks.sol";
import {DistributorHandler} from "./DistributorHandler.sol";

/// @notice Invariants over random call sequences against the value-holding contracts: the
///         distributor (ETH, WETH royalties, IMD mint proceeds) and the collection (supply, claim
///         limits, uniqueness, proceeds split).
/// @dev    One property that *should* hold is deliberately absent here because it does not on the
///         current code: "the sum of pending claims never exceeds the distributor's balance" (and
///         so "a claim with pending value never reverts"). It fails through dust re-attribution in
///         `IMDenzaDistributor.distribute`; see `.imd-findings.json` for the failing sequence. The
///         handler counts those reverts in `blockedClaims` instead of asserting them away.
/// forge-config: default.invariant.runs = 48
/// forge-config: default.invariant.depth = 40
/// forge-config: default.invariant.fail-on-revert = true
contract DistributorInvariants is BaseTest {
    address constant ETH = address(0);

    DistributorHandler handler;
    MockERC20 weth;
    address[] actors;

    function setUp() public override {
        super.setUp();
        weth = new MockERC20("WETH", "WETH", 18);
        actors.push(alice);
        actors.push(bob);
        actors.push(carol);
        actors.push(makeAddr("dave"));
        actors.push(makeAddr("erin"));
        handler = new DistributorHandler(nft, imd, weth, actors);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = handler.claimImd.selector;
        selectors[1] = handler.publicMint.selector;
        selectors[2] = handler.sendEth.selector;
        selectors[3] = handler.sendWeth.selector;
        selectors[4] = handler.sendDust.selector;
        selectors[5] = handler.distribute.selector;
        selectors[6] = handler.claim.selector;
        selectors[7] = handler.claimForOther.selector;
        selectors[8] = handler.claimMixedOwners.selector;
        selectors[9] = handler.transfer.selector;
        selectors[10] = handler.recordJob.selector;
        selectors[11] = handler.advanceChain.selector;
        selectors[12] = handler.distribute.selector; // weight distribution a little higher
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function _assets() internal view returns (address[3] memory a) {
        a = [ETH, address(weth), address(imd)];
    }

    function _balance(address asset) internal view returns (uint256) {
        return asset == ETH ? address(dist).balance : MockERC20(asset).balanceOf(address(dist));
    }

    // ------------------------------------------------------------ value conservation

    /// @notice What the distributor holds is exactly what entered minus what claims paid out.
    function invariant_balanceIsInMinusOut() public view {
        address[3] memory a = _assets();
        for (uint256 i; i < 3; ++i) {
            assertEq(_balance(a[i]), handler.ghostIn(a[i]) - handler.ghostOut(a[i]), "balance != in - out");
            assertLe(handler.ghostOut(a[i]), handler.ghostIn(a[i]), "paid out more than received");
        }
    }

    /// @notice Reserved (attributed but unclaimed) value is always backed by the balance.
    function invariant_reservedIsBackedByBalance() public view {
        address[3] memory a = _assets();
        for (uint256 i; i < 3; ++i) {
            assertLe(dist.reserved(a[i]), _balance(a[i]), "reserved exceeds balance");
        }
    }

    /// @notice reserved == everything ever attributed - everything ever claimed (no other path moves it).
    function invariant_reservedMatchesLedger() public view {
        address[3] memory a = _assets();
        for (uint256 i; i < 3; ++i) {
            assertEq(dist.reserved(a[i]), handler.ghostAttributed(a[i]) - handler.ghostOut(a[i]), "reserved ledger");
            assertLe(handler.ghostAttributed(a[i]), handler.ghostIn(a[i]), "attributed more than received");
        }
    }

    /// @notice The collection itself never retains proceeds: everything is forwarded at mint.
    function invariant_collectionHoldsNoFunds() public view {
        assertEq(imd.balanceOf(address(nft)), 0, "IMD stuck in collection");
        assertEq(address(nft).balance, 0, "ETH stuck in collection");
    }

    /// @notice Treasury got exactly 10% of every public mint, the distributor exactly 90%.
    function invariant_proceedsSplit() public view {
        uint256 paid = handler.ghostPublicPaid();
        assertEq(imd.balanceOf(nft.TREASURY()), handler.ghostTreasury(), "treasury balance");
        assertEq(handler.ghostTreasury(), paid - paid * nft.HOLDER_SHARE_BPS() / nft.BPS(), "treasury share");
        assertEq(handler.ghostHolderProceeds(), paid - handler.ghostTreasury(), "holder share");
        assertLe(handler.ghostHolderProceeds(), handler.ghostIn(address(imd)), "proceeds not in distributor");
    }

    // ------------------------------------------------------------ attribution shape

    /// @notice Checkpoints are strictly increasing in minted count and non-decreasing in accumulator.
    function invariant_checkpointsAreOrdered() public view {
        address[3] memory a = _assets();
        for (uint256 i; i < 3; ++i) {
            uint256 n = dist.checkpointCount(a[i]);
            uint256 lastMinted;
            uint256 lastAcc;
            for (uint256 k; k < n; ++k) {
                IMDenzaDistributor.Checkpoint memory cp = dist.checkpointAt(a[i], k);
                if (k > 0) assertGt(cp.minted, lastMinted, "checkpoint minted not increasing");
                assertGe(cp.acc, lastAcc, "checkpoint acc decreasing");
                assertLe(cp.minted, nft.totalMinted(), "checkpoint beyond supply");
                lastMinted = cp.minted;
                lastAcc = cp.acc;
            }
            if (n > 0) assertEq(lastAcc, dist.accPerToken(a[i]), "last checkpoint != accPerToken");
            else assertEq(dist.accPerToken(a[i]), 0, "acc without checkpoint");
        }
    }

    /// @notice A token minted after the last distribution of an asset has nothing pending for it,
    ///         and tokens that never existed have nothing pending either.
    function invariant_laterTokensShareNothingEarlier() public view {
        address[3] memory a = _assets();
        uint256 minted = nft.totalMinted();
        for (uint256 i; i < 3; ++i) {
            uint256 last = handler.ghostMaxMintedAtDistribution(a[i]);
            for (uint256 id = last + 1; id <= minted; ++id) {
                assertEq(dist.pending(a[i], id), 0, "late token shares earlier value");
            }
            assertEq(dist.pending(a[i], 0), 0, "token 0 pending");
            assertEq(dist.pending(a[i], minted + 1), 0, "unminted token pending");
        }
    }

    /// @notice Every pending amount is bounded by what one token could at most have earned.
    function invariant_pendingBoundedByAccumulator() public view {
        address[3] memory a = _assets();
        uint256 minted = nft.totalMinted();
        for (uint256 i; i < 3; ++i) {
            uint256 cap = dist.accPerToken(a[i]) / dist.PRECISION();
            for (uint256 id = 1; id <= minted; ++id) {
                assertLe(dist.pending(a[i], id), cap, "pending above accumulator");
            }
        }
    }

    // ------------------------------------------------------------ collection

    /// @notice Supply only moves through mints, is capped, and ids are dense 1..totalMinted.
    function invariant_supplyAccounting() public view {
        uint256 minted = nft.totalMinted();
        assertEq(minted, handler.ghostMinted(), "totalMinted != mints observed");
        assertLe(minted, nft.MAX_SUPPLY(), "over cap");
        uint256 held;
        for (uint256 i; i < actors.length; ++i) {
            held += nft.balanceOf(actors[i]);
        }
        assertEq(held, minted, "tokens held by actors != minted");
    }

    /// @notice One IMD-route claim per wallet, mirrored by the on-chain claim flags.
    function invariant_oneFreeClaimPerWalletPerRoute() public view {
        for (uint256 i; i < actors.length; ++i) {
            uint256 c = handler.ghostImdClaims(actors[i]);
            assertLe(c, 1, "more than one IMD claim");
            assertEq(nft.claimFlags(actors[i]) & 2 != 0, c == 1, "claim flag mismatch");
        }
    }

    /// @notice Every token's composition seed and token hash are recorded as used (uniqueness
    ///         itself is asserted by the handler at mint time against all earlier tokens).
    function invariant_everyTokenHasUniqueSeedAndHash() public view {
        uint256 minted = nft.totalMinted();
        for (uint256 id = 1; id <= minted; ++id) {
            bytes32 seed = nft.seedOf(id);
            assertTrue(nft.seedUsed(seed), "seed not marked used");
            assertTrue(handler.ghostSeedSeen(seed), "seed unknown to handler");
            assertTrue(nft.tokenHashUsed(nft.tokenData(id).tokenHash), "hash not marked used");
        }
    }

    /// @notice Nobody can ever take owner-only powers: the collection has no owner.
    function invariant_noOwnerPowers() public {
        vm.expectRevert(abi.encodeWithSignature("NoOwner()"));
        nft.setTransferValidator(address(0));
    }
}
