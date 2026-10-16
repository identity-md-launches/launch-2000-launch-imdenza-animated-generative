// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721C, ERC721OpenZeppelin} from "@limitbreak/creator-token-standards/erc721c/ERC721C.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IMDenzaDistributor} from "./IMDenzaDistributor.sol";
import {IMDenzaRenderer} from "./IMDenzaRenderer.sol";
import {SwarmHistory} from "./SwarmHistory.sol";

/// @dev Subset of Limit Break's CreatorTokenTransferValidator (v4) used to self-configure the
///      collection's royalty-enforcement policy. The collection itself is an authorised caller.
interface ICreatorTokenTransferValidatorPolicy {
    function setTransferSecurityLevelOfCollection(
        address collection,
        uint8 level,
        bool disableAuthorizationMode,
        bool disableWildcardOperators,
        bool enableAccountFreezingMode
    ) external;
    function applyListToCollection(address collection, uint120 id) external;
}

/// @title IMDenza
/// @notice 3333 fully on-chain animated generative flow-field pieces. ERC721C (Limit Break) with
///         6.9% creator earnings paid to a holder distribution contract. No owner, no pause, no
///         upgrade, no discretionary mint: the only mint paths are the three on-chain-checked free
///         claims and the public mint, and all of them end when the supply is reached.
contract IMDenza is ERC721C, IERC2981, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------ constants

    uint256 public constant MAX_SUPPLY = 3333;
    /// @notice 6.9% creator earnings (ERC-2981), paid to `distributor`.
    uint96 public constant ROYALTY_BPS = 690;
    /// @notice Share of mint proceeds that goes to holders; the rest goes to `TREASURY`.
    uint256 public constant HOLDER_SHARE_BPS = 9000;
    uint256 public constant BPS = 10_000;
    /// @notice Treasury named by the brief (receives 10% of mint proceeds).
    address public constant TREASURY = 0xc3F0dEC012784f6d7178104C31A4611c6897756c;
    /// @notice Public mint price: 0.069 IMD, expressed in the paying token's own decimals.
    uint256 public constant MINT_PRICE_MILLI = 69; // thousandths of one IMD
    /// @notice IMD token (Identity.md, 18 decimals, live on mainnet).
    address public constant IMD_TOKEN_A = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    /// @notice Second IMD token address named by the brief (no code on mainnet at build time; checked on use).
    address public constant IMD_TOKEN_B = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    /// @notice "More than 25 IMD": strictly greater than 25 whole tokens.
    uint256 public constant IMD_HOLDING_WHOLE = 25;
    /// @notice Art Blocks core contract holding Fidenza (project 78).
    address public constant ART_BLOCKS = 0xa7d8d9ef8D8Ce8992Df33D8b8CF4Aebabd5bD270;
    uint256 public constant FIDENZA_PROJECT = 78;
    uint256 public constant ART_BLOCKS_PROJECT_SIZE = 1_000_000;
    /// @notice ERC721C transfer security level applied: 3 = operator whitelist, OTC transfers allowed.
    uint8 public constant TRANSFER_SECURITY_LEVEL = 3;
    /// @notice Limit Break's default operator whitelist (list id 0) on the default validator.
    uint120 public constant OPERATOR_WHITELIST_ID = 0;
    /// @notice Canonical mainnet WETH (royalties on WETH sales). Attributed to holders before every mint.
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /// @notice Accepted `decimals()` range for paying in an IMD token (below 3 the 0.069 price truncates);
    ///         the holding check only refuses more than `MAX_IMD_DECIMALS`.
    uint8 public constant MIN_IMD_DECIMALS = 3;
    uint8 public constant MAX_IMD_DECIMALS = 36;

    uint8 private constant CLAIM_IDENTITY = 1;
    uint8 private constant CLAIM_IMD = 2;
    uint8 private constant CLAIM_FIDENZA = 4;

    // ------------------------------------------------------------ storage

    struct TokenData {
        bytes32 tokenHash;
        bytes32 swarmEntropy;
        uint64 typeProfile;
        uint32 swarmJobIndex;
        uint32 mintBlock;
    }

    IMDenzaRenderer public immutable renderer;
    SwarmHistory public immutable swarm;
    IMDenzaDistributor public immutable distributor;
    /// @notice The only post-deployment power: set `identityMdCollection` once. See README.
    address public immutable configurator;

    /// @notice Identity MD NFT collection whose holders may claim one piece. Unset until configured.
    address public identityMdCollection;
    uint256 public totalMinted;
    /// @notice Whether the ERC721C policy has been applied on the validator.
    bool public transferPolicyApplied;

    mapping(uint256 => TokenData) private _tokenData;
    mapping(bytes32 => bool) public tokenHashUsed;
    mapping(bytes32 => bool) public seedUsed;
    mapping(address => uint8) public claimFlags;
    mapping(uint256 => bool) public identityTokenUsed;
    mapping(uint256 => bool) public fidenzaTokenUsed;

    // ------------------------------------------------------------ events / errors

    event Minted(
        uint256 indexed tokenId,
        address indexed to,
        bytes32 tokenHash,
        bytes32 swarmEntropy,
        uint256 swarmJobIndex,
        uint8 route
    );
    event ProceedsSplit(address indexed token, uint256 toHolders, uint256 toTreasury);
    event IdentityMdCollectionSet(address collection);
    event TransferPolicyApplied(address validator, uint8 level, uint120 listId);

    error SoldOut();
    error AlreadyClaimed();
    error NotConfigured();
    error NotConfigurator();
    error AlreadyConfigured();
    error ZeroAddress();
    error NotTokenOwner();
    error NotFidenza();
    error TokenAlreadyUsed();
    error InsufficientImd();
    error UnsupportedPaymentToken();
    error NoCode(address target);
    error NoOwner();
    error NonexistentToken();
    error NotErc721(address collection);
    error InvalidCollection();
    error UnsupportedDecimals(address token);
    error UnderPaid(uint256 received, uint256 price);

    // ------------------------------------------------------------ constructor

    /// @param configurator_ Address allowed to set the Identity MD collection once (launch owner).
    /// @param renderer_     IMDenzaRenderer.
    /// @param swarm_        SwarmHistory ledger.
    constructor(address configurator_, address renderer_, address swarm_) ERC721OpenZeppelin("IMDenza", "IMDENZA") {
        if (configurator_ == address(0) || renderer_ == address(0) || swarm_ == address(0)) revert ZeroAddress();
        configurator = configurator_;
        renderer = IMDenzaRenderer(renderer_);
        swarm = SwarmHistory(swarm_);
        distributor = new IMDenzaDistributor();
    }

    // ------------------------------------------------------------ configuration

    /// @notice One-shot: set the Identity MD NFT collection used by `claimWithIdentityMd`. It must be
    ///         a deployed ERC-721 (ERC-165) other than this collection, its distributor or Art Blocks.
    function setIdentityMdCollection(address collection) external {
        if (msg.sender != configurator) revert NotConfigurator();
        if (identityMdCollection != address(0)) revert AlreadyConfigured();
        if (collection == address(0)) revert ZeroAddress();
        if (collection == address(this) || collection == address(distributor) || collection == ART_BLOCKS) {
            revert InvalidCollection();
        }
        if (collection.code.length == 0) revert NoCode(collection);
        if (!_isErc721(collection)) revert NotErc721(collection);
        identityMdCollection = collection;
        emit IdentityMdCollectionSet(collection);
    }

    function _isErc721(address collection) private view returns (bool) {
        (bool ok, bytes memory data) = collection.staticcall{gas: 30_000}(
            abi.encodeWithSelector(IERC165.supportsInterface.selector, type(IERC721).interfaceId)
        );
        return ok && data.length >= 32 && abi.decode(data, (bool));
    }

    /// @notice Apply the fixed ERC721C security policy on the transfer validator so marketplaces
    ///         enforce creator earnings. Permissionless and idempotent; also attempted on first mint.
    function applyTransferPolicy() external {
        _applyTransferPolicy(true);
    }

    function _applyTransferPolicy(bool strict) private {
        address validator = getTransferValidator();
        if (validator.code.length == 0) {
            if (strict) revert NoCode(validator);
            return;
        }
        ICreatorTokenTransferValidatorPolicy v = ICreatorTokenTransferValidatorPolicy(validator);
        if (strict) {
            v.setTransferSecurityLevelOfCollection(address(this), TRANSFER_SECURITY_LEVEL, false, false, false);
            v.applyListToCollection(address(this), OPERATOR_WHITELIST_ID);
        } else {
            try v.setTransferSecurityLevelOfCollection(address(this), TRANSFER_SECURITY_LEVEL, false, false, false) {}
            catch {
                return;
            }
            try v.applyListToCollection(address(this), OPERATOR_WHITELIST_ID) {}
            catch {
                return;
            }
        }
        transferPolicyApplied = true;
        emit TransferPolicyApplied(validator, TRANSFER_SECURITY_LEVEL, OPERATOR_WHITELIST_ID);
    }

    /// @dev ERC721C owner hook: there is no owner, so every owner-only base function reverts.
    function _requireCallerIsContractOwner() internal pure override {
        revert NoOwner();
    }

    // ------------------------------------------------------------ claims

    /// @notice Free claim for a wallet holding an Identity MD NFT. One per wallet, one per NFT.
    function claimWithIdentityMd(uint256 identityTokenId) external nonReentrant returns (uint256 tokenId) {
        address collection = identityMdCollection;
        if (collection == address(0)) revert NotConfigured();
        _checkClaim(CLAIM_IDENTITY);
        if (identityTokenUsed[identityTokenId]) revert TokenAlreadyUsed();
        if (collection.code.length == 0) revert NoCode(collection);
        if (IERC721(collection).ownerOf(identityTokenId) != msg.sender) revert NotTokenOwner();
        identityTokenUsed[identityTokenId] = true;
        tokenId = _mintTo(msg.sender, CLAIM_IDENTITY);
    }

    /// @notice Free claim for a wallet holding more than 25 IMD (either IMD token). One per wallet.
    function claimWithImd() external nonReentrant returns (uint256 tokenId) {
        _checkClaim(CLAIM_IMD);
        if (!_holdsImd(msg.sender)) revert InsufficientImd();
        tokenId = _mintTo(msg.sender, CLAIM_IMD);
    }

    /// @notice Free claim for a wallet holding a Fidenza (Art Blocks project 78). One per wallet, one per Fidenza.
    function claimWithFidenza(uint256 fidenzaTokenId) external nonReentrant returns (uint256 tokenId) {
        _checkClaim(CLAIM_FIDENZA);
        if (fidenzaTokenId / ART_BLOCKS_PROJECT_SIZE != FIDENZA_PROJECT) revert NotFidenza();
        if (fidenzaTokenUsed[fidenzaTokenId]) revert TokenAlreadyUsed();
        if (ART_BLOCKS.code.length == 0) revert NoCode(ART_BLOCKS);
        if (IERC721(ART_BLOCKS).ownerOf(fidenzaTokenId) != msg.sender) revert NotTokenOwner();
        fidenzaTokenUsed[fidenzaTokenId] = true;
        tokenId = _mintTo(msg.sender, CLAIM_FIDENZA);
    }

    function _checkClaim(uint8 flag) private {
        uint8 flags = claimFlags[msg.sender];
        if (flags & flag != 0) revert AlreadyClaimed();
        claimFlags[msg.sender] = flags | flag;
    }

    /// @notice Whether `account` currently holds more than 25 IMD in either IMD token.
    function holdsImd(address account) external view returns (bool) {
        return _holdsImd(account);
    }

    function _holdsImd(address account) private view returns (bool) {
        return _balanceAboveWhole(IMD_TOKEN_A, account) || _balanceAboveWhole(IMD_TOKEN_B, account);
    }

    function _balanceAboveWhole(address token, address account) private view returns (bool) {
        if (token.code.length == 0) return false;
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || data.length < 32) return false;
        uint256 balance = abi.decode(data, (uint256));
        uint8 dec = _decimals(token);
        // 25 whole tokens is exact for any decimals; only an overflowing exponent is refused.
        if (dec > MAX_IMD_DECIMALS) return false;
        return balance > IMD_HOLDING_WHOLE * 10 ** dec;
    }

    function _decimals(address token) private view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Metadata.decimals.selector));
        if (!ok || data.length < 32) return 18;
        uint256 dec = abi.decode(data, (uint256));
        // Out-of-range values map to 255, which the callers refuse.
        return dec > type(uint8).max ? type(uint8).max : uint8(dec);
    }

    // ------------------------------------------------------------ public mint

    /// @notice Current public mint price in `paymentToken` units (0.069 IMD).
    function mintPrice(address paymentToken) public view returns (uint256) {
        if (paymentToken != IMD_TOKEN_A && paymentToken != IMD_TOKEN_B) revert UnsupportedPaymentToken();
        uint8 dec = _decimals(paymentToken);
        if (dec < MIN_IMD_DECIMALS || dec > MAX_IMD_DECIMALS) revert UnsupportedDecimals(paymentToken);
        return MINT_PRICE_MILLI * 10 ** dec / 1000;
    }

    /// @notice Public mint, paid in IMD. 90% of what arrives goes to holders, 10% to the treasury.
    /// @param paymentToken One of the two IMD token addresses (caller must have approved the price).
    function mint(address paymentToken) external nonReentrant returns (uint256 tokenId) {
        uint256 price = mintPrice(paymentToken);
        if (paymentToken.code.length == 0) revert NoCode(paymentToken);
        IERC20 token = IERC20(paymentToken);
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), price);
        uint256 received = token.balanceOf(address(this)) - before;
        if (received < price) revert UnderPaid(received, price);

        tokenId = _mintTo(msg.sender, 0);

        uint256 toHolders = received * HOLDER_SHARE_BPS / BPS;
        uint256 toTreasury = received - toHolders;
        if (toTreasury != 0) token.safeTransfer(TREASURY, toTreasury);
        if (toHolders != 0) {
            token.safeTransfer(address(distributor), toHolders);
            distributor.distribute(paymentToken);
        }
        emit ProceedsSplit(paymentToken, toHolders, toTreasury);
    }

    // ------------------------------------------------------------ mint core

    function _mintTo(address to, uint8 route) private returns (uint256 tokenId) {
        if (totalMinted >= MAX_SUPPLY) revert SoldOut();
        // Attribute royalties and proceeds that arrived earlier to the pieces that existed then,
        // before this piece joins the holder set.
        distributor.sync(_syncAssets());
        tokenId = ++totalMinted;

        if (!transferPolicyApplied) _applyTransferPolicy(false);

        // Token hash from the mint transaction context (Art Blocks style): previous block hash,
        // prevrandao, minter, block number and token id. Reuse of a hash is explicitly refused.
        bytes32 h = keccak256(
            abi.encodePacked(tokenId, blockhash(block.number - 1), block.prevrandao, to, block.number, block.timestamp)
        );
        while (tokenHashUsed[h]) {
            h = keccak256(abi.encodePacked(h));
        }
        tokenHashUsed[h] = true;

        (bytes32 entropy, uint256 jobCount, uint64 profile) = swarm.snapshot();
        bytes32 seed = keccak256(abi.encodePacked(h, entropy, tokenId));
        // Impossible for distinct token ids without a keccak collision; refused regardless.
        if (seedUsed[seed]) revert TokenAlreadyUsed();
        seedUsed[seed] = true;

        _tokenData[tokenId] = TokenData({
            tokenHash: h,
            swarmEntropy: entropy,
            typeProfile: profile,
            swarmJobIndex: uint32(jobCount),
            mintBlock: uint32(block.number)
        });
        emit Minted(tokenId, to, h, entropy, jobCount, route);
        _safeMint(to, tokenId);
    }

    /// @dev Assets attributed before every mint: ETH, both IMD tokens and WETH.
    function _syncAssets() private pure returns (address[] memory assets) {
        assets = new address[](4);
        assets[0] = address(0);
        assets[1] = IMD_TOKEN_A;
        assets[2] = IMD_TOKEN_B;
        assets[3] = WETH;
    }

    // ------------------------------------------------------------ views

    /// @notice Immutable mint data of a token.
    function tokenData(uint256 tokenId) external view returns (TokenData memory) {
        if (!_exists(tokenId)) revert NonexistentToken();
        return _tokenData[tokenId];
    }

    /// @notice Renderer input for a token.
    function piece(uint256 tokenId) public view returns (IMDenzaRenderer.Piece memory) {
        if (!_exists(tokenId)) revert NonexistentToken();
        TokenData memory d = _tokenData[tokenId];
        return IMDenzaRenderer.Piece({
            tokenId: tokenId,
            tokenHash: d.tokenHash,
            swarmEntropy: d.swarmEntropy,
            swarmJobIndex: d.swarmJobIndex,
            typeProfile: d.typeProfile
        });
    }

    /// @notice Composition seed of a token (unique per token by construction).
    function seedOf(uint256 tokenId) external view returns (bytes32) {
        return renderer.seedOf(piece(tokenId));
    }

    /// @notice Readable traits.
    function traits(uint256 tokenId) external view returns (IMDenzaRenderer.Traits memory) {
        return renderer.traits(piece(tokenId));
    }

    /// @notice Raw animated SVG.
    function svg(uint256 tokenId) external view returns (string memory) {
        return renderer.svg(piece(tokenId));
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return renderer.tokenURI(piece(tokenId));
    }

    /// @inheritdoc IERC2981
    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        return (address(distributor), salePrice * ROYALTY_BPS / BPS);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721C, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
