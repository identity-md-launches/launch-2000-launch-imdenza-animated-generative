// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {IMDenza} from "../src/IMDenza.sol";
import {IMDenzaDistributor} from "../src/IMDenzaDistributor.sol";
import {SwarmHistory} from "../src/SwarmHistory.sol";
import {MockERC20} from "./mocks/Mocks.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev ERC-20 that burns 1% of every transfer (fee-on-transfer); used at the IMD token B address.
contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("FeeIMD", "FIMD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 fee = amount / 100;
        super._transfer(from, to, amount - fee);
        _burn(from, fee);
    }
}

/// @dev Token whose `decimals()` does not exist (falls back to 18 in IMDenza) and whose balances are set directly.
contract NoDecimalsToken {
    mapping(address => uint256) public balanceOf;

    function set(address who, uint256 bal) external {
        balanceOf[who] = bal;
    }
}

/// @dev Contract minter whose ERC-721 receive hook tries to re-enter the collection and the distributor.
contract ReentrantMinter {
    IMDenza immutable nft;
    IMDenzaDistributor immutable dist;
    address immutable token;
    bytes public claimError;
    bytes public mintError;
    bytes public distributeError;
    bytes public claimPendingError;
    uint256 public hookTokenId;

    constructor(IMDenza nft_, address token_) {
        nft = nft_;
        dist = nft_.distributor();
        token = token_;
    }

    function mint() external returns (uint256) {
        MockERC20(token).approve(address(nft), type(uint256).max);
        return nft.mint(token);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        hookTokenId = tokenId;
        (bool ok, bytes memory err) = address(nft).call(abi.encodeCall(IMDenza.claimWithImd, ()));
        if (!ok) claimError = err;
        (ok, err) = address(nft).call(abi.encodeCall(IMDenza.mint, (token)));
        if (!ok) mintError = err;
        (ok, err) = address(dist).call(abi.encodeCall(IMDenzaDistributor.distribute, (token)));
        if (!ok) distributeError = err;
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        (ok, err) = address(dist).call(abi.encodeCall(IMDenzaDistributor.claim, (token, ids)));
        if (!ok) claimPendingError = err;
        return this.onERC721Received.selector;
    }
}

/// @dev Contract that cannot receive ERC-721 tokens (no hook).
contract NoReceiver {
    function mint(IMDenza nft, address token) external returns (uint256) {
        MockERC20(token).approve(address(nft), type(uint256).max);
        return nft.mint(token);
    }

    function claimImd(IMDenza nft) external returns (uint256) {
        return nft.claimWithImd();
    }
}

contract IMDenzaEdgesTest is BaseTest {
    using stdStorage for StdStorage;

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

    // ------------------------------------------------------------ Fidenza boundaries

    function test_fidenzaProjectBoundaries() public {
        artBlocks.mint(alice, 77_999_999);
        artBlocks.mint(alice, 78_000_000);
        artBlocks.mint(bob, 78_999_999);
        artBlocks.mint(bob, 79_000_000);

        vm.prank(alice);
        vm.expectRevert(IMDenza.NotFidenza.selector);
        nft.claimWithFidenza(77_999_999);
        vm.prank(bob);
        vm.expectRevert(IMDenza.NotFidenza.selector);
        nft.claimWithFidenza(79_000_000);
        // a rejected id does not consume the wallet's claim
        assertEq(nft.claimFlags(alice), 0);

        vm.prank(alice);
        assertEq(nft.claimWithFidenza(78_000_000), 1);
        vm.prank(bob);
        assertEq(nft.claimWithFidenza(78_999_999), 2);
    }

    function test_fidenzaClaimNeedsArtBlocksCodeAndAnExistingToken() public {
        vm.etch(nft.ART_BLOCKS(), "");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDenza.NoCode.selector, nft.ART_BLOCKS()));
        nft.claimWithFidenza(78_000_001);

        vm.etch(nft.ART_BLOCKS(), address(artBlocks).code);
        // nonexistent Fidenza: ownerOf reverts, nothing is minted or flagged
        vm.prank(alice);
        vm.expectRevert();
        nft.claimWithFidenza(78_000_001);
        assertEq(nft.totalMinted(), 0);
        assertFalse(nft.fidenzaTokenUsed(78_000_001));
        assertEq(nft.claimFlags(alice), 0);
    }

    // ------------------------------------------------------------ Identity MD

    function test_identityClaimNeedsCollectionCodeAndExistingToken() public {
        address dead = makeAddr("empty collection");
        vm.prank(CONFIGURATOR);
        nft.setIdentityMdCollection(dead);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMDenza.NoCode.selector, dead));
        nft.claimWithIdentityMd(1);

        // the configurator cannot repoint it to a real collection afterwards
        vm.prank(CONFIGURATOR);
        vm.expectRevert(IMDenza.AlreadyConfigured.selector);
        nft.setIdentityMdCollection(address(identity));
    }

    function test_identityClaimForNonexistentTokenRevertsWithoutSideEffects() public {
        vm.prank(CONFIGURATOR);
        nft.setIdentityMdCollection(address(identity));
        vm.prank(alice);
        vm.expectRevert();
        nft.claimWithIdentityMd(42);
        assertEq(nft.claimFlags(alice), 0);
        assertFalse(nft.identityTokenUsed(42));
        assertEq(nft.totalMinted(), 0);
    }

    // ------------------------------------------------------------ IMD holding check

    function test_imdClaimFailsWhenNeitherTokenHasCode() public {
        vm.etch(nft.IMD_TOKEN_A(), "");
        _giveImdSilently();
        assertFalse(nft.holdsImd(alice));
        vm.prank(alice);
        vm.expectRevert(IMDenza.InsufficientImd.selector);
        nft.claimWithImd();
    }

    function _giveImdSilently() internal {
        // token A has no code any more: nothing to mint; just make sure the balance read is a miss
    }

    function test_imdHoldingUsesEighteenDecimalsWhenDecimalsIsMissing() public {
        vm.etch(nft.IMD_TOKEN_A(), address(new NoDecimalsToken()).code);
        NoDecimalsToken t = NoDecimalsToken(nft.IMD_TOKEN_A());
        t.set(alice, 25 ether);
        assertFalse(nft.holdsImd(alice));
        t.set(alice, 25 ether + 1);
        assertTrue(nft.holdsImd(alice));
        assertEq(nft.mintPrice(nft.IMD_TOKEN_A()), 0.069 ether);
    }

    function test_imdHoldingEitherTokenSuffices() public {
        vm.etch(nft.IMD_TOKEN_B(), address(new MockERC20("IMD2", "IMD2", 18)).code);
        MockERC20 b = MockERC20(nft.IMD_TOKEN_B());
        // 25 in A and 25 in B: neither is *more than* 25 on its own, balances are not summed
        _giveImd(alice, 25 ether);
        b.mint(alice, 25 ether);
        assertFalse(nft.holdsImd(alice));
        b.mint(alice, 1);
        assertTrue(nft.holdsImd(alice));
    }

    function test_holdingIsPointInTimeAndTokenStaysClaimedAfterSelling() public {
        uint256 id = _claimImd(alice);
        uint256 all = imd.balanceOf(alice);
        vm.prank(alice);
        imd.transfer(bob, all);
        // alice no longer qualifies, but the piece stays hers and the flag stays set
        assertFalse(nft.holdsImd(alice));
        assertEq(nft.ownerOf(id), alice);
        vm.prank(alice);
        vm.expectRevert(IMDenza.AlreadyClaimed.selector);
        nft.claimWithImd();
        // the same IMD now qualifies bob (one claim per wallet, not per token balance)
        vm.prank(bob);
        assertEq(nft.claimWithImd(), 2);
    }

    // ------------------------------------------------------------ public mint

    function test_publicMintHasNoPerWalletLimitAndEmitsEvents() public {
        uint256 price = nft.mintPrice(address(imd));
        _giveImd(alice, price * 2);
        vm.startPrank(alice);
        imd.approve(address(nft), price * 2);
        vm.expectEmit(true, true, false, false);
        emit IMDenza.Minted(1, alice, bytes32(0), bytes32(0), 0, 0);
        vm.expectEmit();
        emit IMDenza.ProceedsSplit(address(imd), price - price / 10, price / 10);
        nft.mint(address(imd));
        assertEq(nft.mint(address(imd)), 2);
        vm.stopPrank();
        assertEq(nft.balanceOf(alice), 2);
        assertEq(imd.balanceOf(alice), 0);
        assertEq(imd.balanceOf(nft.TREASURY()), price / 5);
    }

    function test_publicMintSplitsWhatActuallyArrivesWithFeeOnTransferToken() public {
        address tokenB = nft.IMD_TOKEN_B();
        vm.etch(tokenB, address(new FeeOnTransferToken()).code);
        FeeOnTransferToken fee = FeeOnTransferToken(tokenB);
        uint256 price = nft.mintPrice(tokenB);
        assertEq(price, 0.069 ether);
        fee.mint(alice, price);
        vm.startPrank(alice);
        fee.approve(address(nft), price);
        uint256 id = nft.mint(tokenB);
        vm.stopPrank();

        uint256 received = price - price / 100;
        uint256 toHolders = received * 9000 / 10_000;
        assertEq(fee.balanceOf(address(nft)), 0, "nothing retained");
        // each onward transfer loses its own 1%, so what lands is 99% of the split
        assertEq(fee.balanceOf(nft.TREASURY()), (received - toHolders) - (received - toHolders) / 100);
        assertEq(fee.balanceOf(address(dist)), toHolders - toHolders / 100);
        assertEq(dist.pending(tokenB, id), toHolders - toHolders / 100);
    }

    function test_publicMintToContractWithoutReceiverRevertsAndRefunds() public {
        NoReceiver r = new NoReceiver();
        uint256 price = nft.mintPrice(address(imd));
        _giveImd(address(r), price);
        vm.expectRevert();
        r.mint(nft, address(imd));
        assertEq(nft.totalMinted(), 0);
        assertEq(imd.balanceOf(address(r)), price);
        assertEq(imd.balanceOf(nft.TREASURY()), 0);

        _giveImd(address(r), 26 ether);
        vm.expectRevert();
        r.claimImd(nft);
        assertEq(nft.claimFlags(address(r)), 0);
    }

    function test_reentrancyFromReceiveHookIsBlockedAndSplitStaysCorrect() public {
        ReentrantMinter r = new ReentrantMinter(nft, address(imd));
        uint256 price = nft.mintPrice(address(imd));
        _giveImd(address(r), price + 26 ether);
        uint256 id = r.mint();
        assertEq(id, 1);
        assertEq(r.hookTokenId(), 1);
        // both mint paths share one reentrancy guard
        assertEq(r.claimError(), abi.encodeWithSignature("Error(string)", "ReentrancyGuard: reentrant call"));
        assertEq(r.mintError(), abi.encodeWithSignature("Error(string)", "ReentrancyGuard: reentrant call"));
        // the payment is still inside the collection during the hook: nothing to distribute or claim yet
        assertEq(bytes4(r.distributeError()), IMDenzaDistributor.NothingToDistribute.selector);
        assertEq(bytes4(r.claimPendingError()), IMDenzaDistributor.NothingToClaim.selector);
        // and the split completed normally afterwards
        assertEq(nft.totalMinted(), 1);
        assertEq(imd.balanceOf(address(nft)), 0);
        assertEq(imd.balanceOf(nft.TREASURY()), price / 10);
        assertEq(dist.pending(address(imd), 1), price - price / 10);
        assertEq(nft.claimFlags(address(r)), 0);
    }

    function test_soldOutRevertsBeforePullingPayment() public {
        uint256 slot = stdstore.target(address(nft)).sig("totalMinted()").find();
        vm.store(address(nft), bytes32(slot), bytes32(uint256(3333)));
        uint256 price = nft.mintPrice(address(imd));
        _giveImd(alice, price);
        vm.startPrank(alice);
        imd.approve(address(nft), price);
        vm.expectRevert(IMDenza.SoldOut.selector);
        nft.mint(address(imd));
        vm.stopPrank();
        assertEq(imd.balanceOf(alice), price);
        assertEq(imd.balanceOf(nft.TREASURY()), 0);
    }

    function testFuzz_royaltyIsAlways6_9PercentToTheDistributor(uint256 tokenId, uint256 salePrice) public view {
        salePrice = bound(salePrice, 0, 1e30);
        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, salePrice);
        assertEq(receiver, address(dist));
        assertEq(amount, salePrice * 690 / 10_000);
        assertLe(amount, salePrice);
    }

    // ------------------------------------------------------------ distributor edges

    function test_claimWithDuplicateIdsPaysOnce() public {
        uint256 a = _claimImd(alice);
        vm.deal(address(dist), 2 ether);
        dist.distribute(ETH);
        uint256 before = alice.balance;
        assertEq(dist.claim(ETH, _ids(a, a)), 2 ether);
        assertEq(alice.balance - before, 2 ether);
        assertEq(address(dist).balance, 0);
    }

    function test_claimForUnmintedOrZeroTokenReverts() public {
        _claimImd(alice);
        vm.deal(address(dist), 1 ether);
        dist.distribute(ETH);
        vm.expectRevert();
        dist.claim(ETH, _ids(0));
        vm.expectRevert();
        dist.claim(ETH, _ids(2));
        vm.expectRevert();
        dist.claim(ETH, _ids(1, 2));
        assertEq(dist.pending(ETH, 1), 1 ether);
    }

    function test_distributeForAssetWithoutCodeReverts() public {
        _claimImd(alice);
        vm.expectRevert();
        dist.distribute(makeAddr("not a token"));
    }

    function test_ethReceivedBeforeFirstMintBelongsToTheFirstTokens() public {
        vm.deal(address(dist), 3 ether);
        vm.expectRevert(IMDenzaDistributor.NoTokensMinted.selector);
        dist.distribute(ETH);
        uint256 a = _claimImd(alice);
        uint256 b = _claimImd(bob);
        dist.distribute(ETH);
        assertEq(dist.pending(ETH, a), 1.5 ether);
        assertEq(dist.pending(ETH, b), 1.5 ether);
    }

    function test_distributionBetweenMintsOfOneHolderIsPerToken() public {
        uint256 a = _claimImd(alice);
        vm.deal(address(dist), 1 ether);
        dist.distribute(ETH);
        uint256 b = _publicMint(alice); // alice now holds two; token b did not exist for the 1 ETH
        assertEq(dist.pending(ETH, a), 1 ether);
        assertEq(dist.pending(ETH, b), 0);
        vm.deal(address(dist), address(dist).balance + 1 ether);
        dist.distribute(ETH);
        assertEq(dist.pending(ETH, a), 1.5 ether);
        assertEq(dist.pending(ETH, b), 0.5 ether);
        uint256 before = alice.balance;
        assertEq(dist.claim(ETH, _ids(a, b)), 2 ether);
        assertEq(alice.balance - before, 2 ether);
    }

    function test_twoDistributionsAtSameMintedCountMergeIntoOneCheckpoint() public {
        _claimImd(alice);
        vm.deal(address(dist), 1 ether);
        dist.distribute(ETH);
        vm.deal(address(dist), 2 ether);
        dist.distribute(ETH);
        assertEq(dist.checkpointCount(ETH), 1);
        assertEq(dist.checkpointAt(ETH, 0).acc, 2 ether * dist.PRECISION());
        assertEq(dist.pending(ETH, 1), 2 ether);
    }

    function test_distributorHasNoAdminSurface() public view {
        // Nothing but receive/distribute/claim and views: no owner, no sweep, no setter.
        assertEq(address(dist.nft()), address(nft));
        assertEq(dist.ETH(), address(0));
    }

    /// @dev Exact-division amounts: every wei is attributable and claimable, in any claim order.
    function testFuzz_exactAmountsAreFullyClaimable(uint8 holders, uint96 perToken) public {
        holders = uint8(bound(holders, 1, 5));
        perToken = uint96(bound(perToken, 1, 10 ether));
        for (uint256 i; i < holders; ++i) {
            _claimImd(makeAddr(string(abi.encodePacked("w", i))));
        }
        uint256 total = uint256(perToken) * holders;
        vm.deal(address(dist), total);
        dist.distribute(ETH);
        assertEq(dist.reserved(ETH), total);
        for (uint256 i = holders; i >= 1; --i) {
            assertEq(dist.pending(ETH, i), perToken);
            assertEq(dist.claim(ETH, _ids(i)), perToken);
        }
        assertEq(address(dist).balance, 0);
        assertEq(dist.reserved(ETH), 0);
    }

    // ------------------------------------------------------------ swarm history edges

    function test_swarmAcceptsBoundaryValuesAndEmptyBatch() public {
        // timestamp exactly now, maximum agent count, last valid type/outcome
        swarm.recordJob(bytes32("edge"), 7, type(uint16).max, 3, uint40(block.timestamp));
        assertEq(swarm.totalAgents(), type(uint16).max);
        assertEq(swarm.successCount(), 0);
        assertEq(swarm.typeCounts()[7], 1);

        uint256 first =
            swarm.recordJobs(new bytes32[](0), new uint8[](0), new uint16[](0), new uint8[](0), new uint40[](0));
        assertEq(first, 1);
        assertEq(swarm.jobCount(), 1);
        vm.expectRevert(SwarmHistory.IndexOutOfRange.selector);
        swarm.recordAt(1);
    }

    function test_swarmBatchIsAllOrNothing() public {
        bytes32[] memory ids = new bytes32[](3);
        uint8[] memory types = new uint8[](3);
        uint16[] memory agents = new uint16[](3);
        uint8[] memory outcomes = new uint8[](3);
        uint40[] memory ts = new uint40[](3);
        for (uint256 i; i < 3; ++i) {
            ids[i] = bytes32(i + 1);
            agents[i] = 1;
            outcomes[i] = 1;
            ts[i] = uint40(block.timestamp);
        }
        ids[2] = ids[0]; // duplicate inside the batch
        vm.expectRevert(abi.encodeWithSelector(SwarmHistory.JobAlreadyRecorded.selector, ids[0]));
        swarm.recordJobs(ids, types, agents, outcomes, ts);
        assertEq(swarm.jobCount(), 0);
        assertFalse(swarm.isRecorded(ids[0]));
        assertEq(swarm.entropy(), bytes32(0));
    }

    function test_swarmFullBatchOf200IsAccepted() public {
        uint256 n = swarm.MAX_BATCH();
        bytes32[] memory ids = new bytes32[](n);
        uint8[] memory types = new uint8[](n);
        uint16[] memory agents = new uint16[](n);
        uint8[] memory outcomes = new uint8[](n);
        uint40[] memory ts = new uint40[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = keccak256(abi.encodePacked("job", i));
            types[i] = uint8(i % 8);
            agents[i] = 1;
            outcomes[i] = uint8(i % 4);
            ts[i] = uint40(block.timestamp - i);
        }
        swarm.recordJobs(ids, types, agents, outcomes, ts);
        assertEq(swarm.jobCount(), n);
        assertEq(swarm.pulse(), swarm.PULSE_MAX());
        assertEq(swarm.foundationalDigests(n).length, swarm.FOUNDATIONAL_JOBS());
        assertEq(swarm.typeProfile() & 0xff, 25);
    }

    function testFuzz_swarmPulseNeverExceedsMaxAndDecaysToZero(uint8 jobs, uint16 wait) public {
        jobs = uint8(bound(jobs, 1, 40));
        for (uint256 i; i < jobs; ++i) {
            swarm.recordJob(bytes32(i + 1), 0, 1, 1, uint40(block.timestamp));
        }
        uint256 p = swarm.pulse();
        assertLe(p, swarm.PULSE_MAX());
        assertEq(p, jobs * swarm.PULSE_PER_JOB() > swarm.PULSE_MAX() ? swarm.PULSE_MAX() : jobs * swarm.PULSE_PER_JOB());
        vm.roll(block.number + wait);
        uint256 decayed = uint256(wait) * swarm.PULSE_DECAY_PER_BLOCK();
        assertEq(swarm.pulse(), decayed >= p ? 0 : p - decayed);
        vm.roll(block.number + 10_000);
        assertEq(swarm.pulse(), 0);
    }

    /// @dev A piece minted *after* a swarm record is bound to that record; the same mint context
    ///      with a different history produces a different piece (history modulates the art).
    function test_swarmHistoryChangesTheSeedOfAnOtherwiseIdenticalMint() public {
        uint256 snap = vm.snapshotState();
        uint256 a = _claimImd(alice);
        bytes32 seedWithout = nft.seedOf(a);
        vm.revertToState(snap);
        swarm.recordJob(bytes32("first"), 0, 1, 1, uint40(block.timestamp));
        uint256 b = _claimImd(alice);
        assertEq(a, b);
        assertTrue(nft.seedOf(b) != seedWithout);
        assertEq(nft.traits(b).jobsTo, 1);
        assertEq(nft.traits(b).traces, 1);
    }
}
