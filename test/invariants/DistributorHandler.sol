// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {IMDenza} from "../../src/IMDenza.sol";
import {IMDenzaDistributor} from "../../src/IMDenzaDistributor.sol";
import {SwarmHistory} from "../../src/SwarmHistory.sol";
import {MockERC20} from "../mocks/Mocks.sol";

/// @notice Drives IMDenza + IMDenzaDistributor with bounded random calls from a small set of
///         actors and keeps ghost totals of everything that entered or left the distributor.
/// @dev    Every action is a top-level call from the invariant runner, so each one is its own
///         transaction, as on chain. Reverts that the protocol must produce are asserted on the
///         spot (wrong claimer, nothing to claim, nothing to distribute); reverts a correct
///         implementation would never produce are counted in `blockedClaims` (see the finding
///         about dust re-attribution in `.imd-findings.json`) rather than asserted away.
contract DistributorHandler is CommonBase, StdCheats, StdUtils {
    address public constant ETH = address(0);

    IMDenza public immutable nft;
    IMDenzaDistributor public immutable dist;
    SwarmHistory public immutable swarm;
    MockERC20 public immutable imd;
    MockERC20 public immutable weth;

    address[] public actors;
    address[3] public assets;

    // ---- ghosts: value flow
    mapping(address => uint256) public ghostIn; // asset => value that entered the distributor
    mapping(address => uint256) public ghostOut; // asset => value paid out by claims
    mapping(address => uint256) public ghostAttributed; // asset => sum of Distributed amounts
    mapping(address => uint256) public ghostMaxMintedAtDistribution; // asset => highest minted count seen by distribute
    mapping(address => uint256) public ghostDistributions; // asset => successful distribute calls
    uint256 public ghostTreasury; // IMD that must have reached TREASURY
    uint256 public ghostPublicPaid; // IMD pulled from public minters
    uint256 public ghostHolderProceeds; // IMD mint proceeds forwarded to the distributor

    // ---- ghosts: collection
    uint256 public ghostMinted;
    mapping(address => uint256) public ghostImdClaims; // actor => claims through the IMD route
    mapping(bytes32 => bool) public ghostSeedSeen;
    mapping(bytes32 => bool) public ghostHashSeen;

    // ---- counters for the report
    uint256 public blockedClaims; // claims with pending > 0 that reverted (should be impossible)
    uint256 public successfulClaims;
    uint256 public calls;

    constructor(IMDenza nft_, MockERC20 imd_, MockERC20 weth_, address[] memory actors_) {
        nft = nft_;
        dist = nft_.distributor();
        swarm = nft_.swarm();
        imd = imd_;
        weth = weth_;
        actors = actors_;
        assets = [ETH, address(weth_), address(imd_)];
    }

    // ------------------------------------------------------------ helpers

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _asset(uint256 seed) internal view returns (address) {
        return assets[bound(seed, 0, 2)];
    }

    function _balance(address asset) internal view returns (uint256) {
        return asset == ETH ? address(dist).balance : MockERC20(asset).balanceOf(address(dist));
    }

    function _balanceOf(address asset, address who) internal view returns (uint256) {
        return asset == ETH ? who.balance : MockERC20(asset).balanceOf(who);
    }

    function _recordMint(uint256 tokenId, address to) internal {
        require(tokenId == ghostMinted + 1, "ids must be sequential");
        ghostMinted = tokenId;
        require(nft.ownerOf(tokenId) == to, "minted to wrong owner");
        bytes32 seed = nft.seedOf(tokenId);
        bytes32 hash = nft.tokenData(tokenId).tokenHash;
        require(!ghostSeedSeen[seed], "duplicate composition seed");
        require(!ghostHashSeen[hash], "duplicate token hash");
        ghostSeedSeen[seed] = true;
        ghostHashSeen[hash] = true;
    }

    // ------------------------------------------------------------ actions: minting

    /// @notice Free claim through the IMD-holding route. Second attempt per wallet must revert.
    function claimImd(uint256 actorSeed) external {
        ++calls;
        address who = _actor(actorSeed);
        imd.mint(who, 26 ether);
        if (nft.totalMinted() >= nft.MAX_SUPPLY()) return;
        vm.prank(who);
        if (ghostImdClaims[who] != 0) {
            try nft.claimWithImd() {
                revert("second IMD claim accepted");
            } catch (bytes memory err) {
                require(bytes4(err) == IMDenza.AlreadyClaimed.selector, "unexpected claim revert");
            }
            return;
        }
        uint256 id = nft.claimWithImd();
        ghostImdClaims[who] += 1;
        _recordMint(id, who);
    }

    /// @notice Public mint paid in IMD; 10% must land in the treasury, 90% in the distributor.
    function publicMint(uint256 actorSeed) external {
        ++calls;
        address who = _actor(actorSeed);
        if (nft.totalMinted() >= nft.MAX_SUPPLY()) return;
        uint256 price = nft.mintPrice(address(imd));
        imd.mint(who, price);
        uint256 treasuryBefore = imd.balanceOf(nft.TREASURY());
        uint256 distBefore = imd.balanceOf(address(dist));
        uint256 reservedBefore = dist.reserved(address(imd));
        vm.startPrank(who);
        imd.approve(address(nft), price);
        uint256 id = nft.mint(address(imd));
        vm.stopPrank();
        _recordMint(id, who);

        uint256 toTreasury = price - (price * nft.HOLDER_SHARE_BPS() / nft.BPS());
        require(imd.balanceOf(nft.TREASURY()) - treasuryBefore == toTreasury, "treasury share");
        require(imd.balanceOf(address(dist)) - distBefore == price - toTreasury, "holder share");
        ghostTreasury += toTreasury;
        ghostPublicPaid += price;
        ghostHolderProceeds += price - toTreasury;
        ghostIn[address(imd)] += price - toTreasury;
        // mint() distributes immediately; that distribution saw the new token.
        ghostDistributions[address(imd)] += 1;
        ghostMaxMintedAtDistribution[address(imd)] = id;
        ghostAttributed[address(imd)] += dist.reserved(address(imd)) - reservedBefore;
    }

    // ------------------------------------------------------------ actions: value in

    function sendEth(uint256 amount) external {
        ++calls;
        amount = bound(amount, 0, 5 ether);
        vm.deal(address(this), amount);
        (bool ok,) = address(dist).call{value: amount}("");
        require(ok, "eth in");
        ghostIn[ETH] += amount;
    }

    function sendWeth(uint256 amount) external {
        ++calls;
        amount = bound(amount, 0, 5 ether);
        weth.mint(address(dist), amount);
        ghostIn[address(weth)] += amount;
    }

    /// @notice Tiny amounts exercise the rounding paths (a few wei over a few tokens).
    function sendDust(uint256 assetSeed, uint256 amount) external {
        ++calls;
        address asset = _asset(assetSeed);
        amount = bound(amount, 1, 1000);
        if (asset == ETH) {
            vm.deal(address(this), amount);
            (bool ok,) = address(dist).call{value: amount}("");
            require(ok, "eth in");
        } else {
            MockERC20(asset).mint(address(dist), amount);
        }
        ghostIn[asset] += amount;
    }

    // ------------------------------------------------------------ actions: distribute / claim

    function distribute(uint256 assetSeed) external {
        ++calls;
        address asset = _asset(assetSeed);
        uint256 minted = nft.totalMinted();
        uint256 unattributed = _balance(asset) - dist.reserved(asset);
        uint256 reservedBefore = dist.reserved(asset);
        try dist.distribute(asset) {
            require(minted != 0, "distributed with no tokens");
            require(unattributed != 0, "distributed nothing");
            ghostDistributions[asset] += 1;
            if (minted > ghostMaxMintedAtDistribution[asset]) ghostMaxMintedAtDistribution[asset] = minted;
            ghostAttributed[asset] += dist.reserved(asset) - reservedBefore;
        } catch (bytes memory err) {
            bytes4 sel = bytes4(err);
            if (minted == 0) {
                require(sel == IMDenzaDistributor.NoTokensMinted.selector, "wrong revert: no tokens");
            } else {
                require(unattributed == 0, "distribute refused with value to attribute");
                require(sel == IMDenzaDistributor.NothingToDistribute.selector, "wrong revert: nothing");
            }
        }
    }

    /// @notice Claim a random subset of one actor's tokens (possibly with a duplicate id) for one asset.
    function claim(uint256 actorSeed, uint256 assetSeed, uint256 pick) external {
        ++calls;
        address who = _actor(actorSeed);
        address asset = _asset(assetSeed);
        uint256 minted = nft.totalMinted();
        if (minted == 0) return;

        // collect the actor's tokens
        uint256[] memory owned = new uint256[](minted);
        uint256 n;
        for (uint256 id = 1; id <= minted; ++id) {
            if (nft.ownerOf(id) == who) owned[n++] = id;
        }
        if (n == 0) return;
        uint256 take = bound(pick, 1, n);
        bool duplicate = pick % 7 == 0;
        uint256[] memory ids = new uint256[](duplicate ? take + 1 : take);
        for (uint256 i; i < take; ++i) {
            ids[i] = owned[i];
        }
        if (duplicate) ids[take] = owned[0]; // a repeated id must not pay twice

        // `pending` floors per token; `claim` sums accumulator units and floors once, so a batch may
        // pay up to (take - 1) wei more than the per-token views add up to.
        uint256 low;
        for (uint256 i; i < take; ++i) {
            low += dist.pending(asset, ids[i]);
        }
        uint256 high = low + take - 1;
        uint256 before = _balanceOf(asset, who);
        uint256 reservedBefore = dist.reserved(asset);
        try dist.claim(asset, ids) returns (uint256 paid) {
            require(paid != 0, "paid a claim with nothing pending");
            require(paid >= low && paid <= high, "paid outside [sum pending, sum pending + n - 1]");
            require(_balanceOf(asset, who) - before == paid, "owner did not receive the claim");
            require(reservedBefore - dist.reserved(asset) == paid, "reserved not reduced by claim");
            for (uint256 i; i < ids.length; ++i) {
                require(dist.pending(asset, ids[i]) == 0, "pending left after claim");
            }
            ghostOut[asset] += paid;
            ++successfulClaims;
        } catch (bytes memory err) {
            if (bytes4(err) == IMDenzaDistributor.NothingToClaim.selector) {
                require(low == 0, "NothingToClaim with pending value");
            } else {
                // A claim with pending value should never revert for an EOA owner. It does when the
                // dust re-attribution drives `reserved` below what is owed (reported, not asserted).
                ++blockedClaims;
            }
        }
    }

    /// @notice Claiming someone else's token pays the owner, never the caller.
    function claimForOther(uint256 callerSeed, uint256 assetSeed, uint256 idSeed) external {
        ++calls;
        uint256 minted = nft.totalMinted();
        if (minted == 0) return;
        address caller = _actor(callerSeed);
        address asset = _asset(assetSeed);
        uint256 id = bound(idSeed, 1, minted);
        address owner = nft.ownerOf(id);
        if (owner == caller) return;
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        uint256 expected = dist.pending(asset, id);
        uint256 ownerBefore = _balanceOf(asset, owner);
        uint256 callerBefore = _balanceOf(asset, caller);
        vm.prank(caller);
        try dist.claim(asset, ids) returns (uint256 paid) {
            require(paid == expected && expected != 0, "wrong amount paid for other");
            require(_balanceOf(asset, owner) - ownerBefore == paid, "owner not paid");
            require(_balanceOf(asset, caller) == callerBefore, "caller must not receive anything");
            ghostOut[asset] += paid;
            ++successfulClaims;
        } catch (bytes memory err) {
            if (expected == 0) require(bytes4(err) == IMDenzaDistributor.NothingToClaim.selector, "wrong revert");
            else ++blockedClaims;
        }
    }

    /// @notice A mixed-owner claim must be refused as a whole.
    function claimMixedOwners(uint256 assetSeed) external {
        ++calls;
        uint256 minted = nft.totalMinted();
        if (minted < 2) return;
        address asset = _asset(assetSeed);
        uint256 a;
        uint256 b;
        for (uint256 id = 1; id <= minted && b == 0; ++id) {
            if (a == 0) a = id;
            else if (nft.ownerOf(id) != nft.ownerOf(a)) b = id;
        }
        if (b == 0) return;
        uint256[] memory ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;
        uint256 pa = dist.pending(asset, a);
        uint256 pb = dist.pending(asset, b);
        try dist.claim(asset, ids) {
            revert("mixed-owner claim accepted");
        } catch (bytes memory err) {
            require(bytes4(err) == IMDenzaDistributor.NotOwnerOfAll.selector, "wrong revert for mixed owners");
        }
        require(dist.pending(asset, a) == pa && dist.pending(asset, b) == pb, "failed claim changed pending");
    }

    // ------------------------------------------------------------ actions: transfers / history

    /// @notice Unclaimed value travels with the token.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 idSeed) external {
        ++calls;
        uint256 minted = nft.totalMinted();
        if (minted == 0) return;
        uint256 id = bound(idSeed, 1, minted);
        address from = nft.ownerOf(id);
        address to = _actor(toSeed);
        if (to == from) to = _actor(fromSeed);
        if (to == from) return;
        uint256[3] memory pend;
        for (uint256 i; i < 3; ++i) {
            pend[i] = dist.pending(assets[i], id);
        }
        vm.prank(from);
        nft.transferFrom(from, to, id);
        require(nft.ownerOf(id) == to, "transfer failed");
        for (uint256 i; i < 3; ++i) {
            require(dist.pending(assets[i], id) == pend[i], "pending changed on transfer");
        }
    }

    function recordJob(bytes32 jobId, uint8 jobType, uint16 agents, uint8 outcome) external {
        ++calls;
        if (swarm.isRecorded(jobId)) return;
        swarm.recordJob(
            jobId,
            uint8(bound(jobType, 0, 7)),
            uint16(bound(agents, 1, 500)),
            uint8(bound(outcome, 0, 3)),
            uint40(block.timestamp)
        );
    }

    function advanceChain(uint256 blocks) external {
        ++calls;
        blocks = bound(blocks, 1, 500);
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * 12);
        vm.prevrandao(keccak256(abi.encodePacked(block.number)));
    }

    receive() external payable {}
}
