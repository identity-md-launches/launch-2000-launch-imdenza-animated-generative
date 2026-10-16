// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IIMDenzaSupply {
    function totalMinted() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title IMDenzaDistributor
/// @notice Splits everything it receives (ETH, IMD mint proceeds, ERC-20 royalties such as WETH)
///         pro-rata to IMDenza holders, one equal share per token. No admin, no redirection.
/// @dev    Accounting is per asset and per token id. IMDenza token ids are minted sequentially
///         (1, 2, 3, ...), so a distribution made when `m` tokens exist belongs to ids 1..m.
///         For each asset we keep checkpoints `(mintedCount, accPerTokenAfter)`; a token's
///         entitlement is `acc - accBefore(tokenId)` where `accBefore` is the accumulator value at
///         the last checkpoint whose minted count is below the token id (found by binary search).
///         Unclaimed value travels with the token on transfer: a claim always pays the current owner.
contract IMDenzaDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Accumulator precision.
    uint256 public constant PRECISION = 1e18;
    /// @notice Asset id used for native ETH.
    address public constant ETH = address(0);

    struct Checkpoint {
        uint256 minted;
        uint256 acc;
    }

    error OnlyNft();
    error NoTokensMinted();
    error NothingToClaim();
    error EthTransferFailed();
    error EmptyClaim();
    error NotOwnerOfAll();

    event Distributed(address indexed asset, uint256 amount, uint256 mintedCount);
    event Claimed(address indexed asset, address indexed to, uint256 amount, uint256[] tokenIds);

    /// @notice The IMDenza collection (the contract that created this distributor).
    IIMDenzaSupply public immutable nft;

    /// @notice asset => accumulated value per token (scaled by PRECISION).
    mapping(address => uint256) public accPerToken;
    /// @notice asset => value backing the accumulators that has not been claimed yet. It covers every
    ///         acc unit credited (rounded up per distribution), so claims can never exceed it.
    mapping(address => uint256) public reserved;
    /// @notice asset => checkpoints, strictly increasing by `minted`.
    mapping(address => Checkpoint[]) private _checkpoints;
    /// @notice asset => tokenId => acc units already paid out (always whole wei times PRECISION).
    mapping(address => mapping(uint256 => uint256)) public claimedAcc;

    constructor() {
        nft = IIMDenzaSupply(msg.sender);
    }

    /// @notice Native ETH royalties (OpenSea pays ETH sales in ETH).
    receive() external payable {}

    /// @notice Attribute any unattributed balance of `asset` to the tokens minted so far.
    ///         Permissionless: anyone may call it after sending value here. A call with nothing new
    ///         to attribute (or less than one acc unit per token) changes nothing and returns 0.
    /// @param asset ERC-20 address, or `ETH` (zero address) for native ETH.
    /// @return amount Value newly reserved for holders.
    function distribute(address asset) external nonReentrant returns (uint256 amount) {
        uint256 minted = nft.totalMinted();
        if (minted == 0) revert NoTokensMinted();
        uint256 balance = asset == ETH ? address(this).balance : IERC20(asset).balanceOf(address(this));
        amount = _attribute(asset, balance, minted);
    }

    /// @notice Attribute the pending balance of each of `assets` to the tokens minted so far,
    ///         skipping any asset it cannot read. IMDenza calls this before every mint so value that
    ///         arrived earlier is never shared with the piece being minted. Permissionless.
    function sync(address[] calldata assets) external nonReentrant {
        uint256 minted = nft.totalMinted();
        if (minted == 0) return;
        for (uint256 i; i < assets.length; ++i) {
            address asset = assets[i];
            uint256 balance;
            if (asset == ETH) {
                balance = address(this).balance;
            } else {
                if (asset.code.length == 0) continue;
                (bool ok, bytes memory data) =
                    asset.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
                if (!ok || data.length < 32) continue;
                balance = abi.decode(data, (uint256));
            }
            _attribute(asset, balance, minted);
        }
    }

    /// @dev Credits `perToken` acc units to each of the `minted` tokens and reserves the wei that
    ///      backs them, rounded up (never more than the unattributed balance). Whatever is not
    ///      reserved stays unattributed and joins the next distribution, so a call with no new
    ///      value is a no-op and the accumulators never promise more than `reserved`.
    function _attribute(address asset, uint256 balance, uint256 minted) private returns (uint256 amount) {
        uint256 held = reserved[asset];
        if (balance <= held) return 0;
        uint256 unattributed = balance - held;
        if (unattributed > type(uint256).max / PRECISION) return 0;
        uint256 perToken = (unattributed * PRECISION) / minted;
        if (perToken == 0) return 0;
        amount = (perToken * minted + PRECISION - 1) / PRECISION;
        reserved[asset] = held + amount;
        uint256 acc = accPerToken[asset] + perToken;
        accPerToken[asset] = acc;

        Checkpoint[] storage cps = _checkpoints[asset];
        uint256 n = cps.length;
        if (n > 0 && cps[n - 1].minted == minted) {
            cps[n - 1].acc = acc;
        } else {
            cps.push(Checkpoint({minted: minted, acc: acc}));
        }
        emit Distributed(asset, amount, minted);
    }

    /// @notice Pay the pending `asset` share of `tokenIds` to their owner. All ids must share one
    ///         owner. Anyone may call; payment always goes to the current owner. Each token is paid
    ///         its whole-wei share; the fraction below one wei stays credited to it.
    function claim(address asset, uint256[] calldata tokenIds) external nonReentrant returns (uint256 amount) {
        if (tokenIds.length == 0) revert EmptyClaim();
        address to = nft.ownerOf(tokenIds[0]);
        uint256 acc = accPerToken[asset];
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 id = tokenIds[i];
            if (i != 0 && nft.ownerOf(id) != to) revert NotOwnerOfAll();
            uint256 earned = acc - _accBefore(asset, id);
            uint256 paid = claimedAcc[asset][id];
            uint256 owed = (earned - paid) / PRECISION;
            if (owed != 0) {
                claimedAcc[asset][id] = paid + owed * PRECISION;
                amount += owed;
            }
        }
        if (amount == 0) revert NothingToClaim();
        reserved[asset] -= amount;
        emit Claimed(asset, to, amount, tokenIds);
        if (asset == ETH) {
            (bool ok,) = to.call{value: amount}("");
            if (!ok) revert EthTransferFailed();
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

    /// @notice Pending `asset` amount claimable for `tokenId`.
    function pending(address asset, uint256 tokenId) external view returns (uint256) {
        if (tokenId == 0 || tokenId > nft.totalMinted()) return 0;
        uint256 earned = accPerToken[asset] - _accBefore(asset, tokenId);
        return (earned - claimedAcc[asset][tokenId]) / PRECISION;
    }

    /// @notice Number of checkpoints recorded for `asset`.
    function checkpointCount(address asset) external view returns (uint256) {
        return _checkpoints[asset].length;
    }

    /// @notice Checkpoint `index` of `asset`.
    function checkpointAt(address asset, uint256 index) external view returns (Checkpoint memory) {
        return _checkpoints[asset][index];
    }

    /// @dev Accumulator value at the last checkpoint with `minted < tokenId`, i.e. everything
    ///      distributed before `tokenId` existed.
    function _accBefore(address asset, uint256 tokenId) private view returns (uint256) {
        Checkpoint[] storage cps = _checkpoints[asset];
        uint256 lo;
        uint256 hi = cps.length;
        // Find the first checkpoint with minted >= tokenId.
        while (lo < hi) {
            uint256 mid = (lo + hi) >> 1;
            if (cps[mid].minted < tokenId) lo = mid + 1;
            else hi = mid;
        }
        return lo == 0 ? 0 : cps[lo - 1].acc;
    }
}
