// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC20 is ERC20 {
    uint8 private immutable _dec;

    constructor(string memory n, string memory s, uint8 dec) ERC20(n, s) {
        _dec = dec;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Plain ERC-721 with public mint; used for the Art Blocks core and the Identity MD collection.
contract MockERC721 is ERC721 {
    constructor() ERC721("Mock", "MOCK") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

/// @dev Stand-in for Limit Break's CreatorTokenTransferValidator, etched at the default address.
contract MockTransferValidator {
    struct Policy {
        uint8 level;
        bool disableAuthorizationMode;
        bool disableWildcardOperators;
        bool enableAccountFreezingMode;
        uint120 listId;
        uint16 tokenType;
        uint256 policyCalls;
    }

    mapping(address => Policy) public policies;
    mapping(address => bool) public blockedOperator;
    bool public revertOnPolicy;

    function setBlockedOperator(address op, bool blocked) external {
        blockedOperator[op] = blocked;
    }

    function setRevertOnPolicy(bool v) external {
        revertOnPolicy = v;
    }

    function setTransferSecurityLevelOfCollection(address collection, uint8 level, bool a, bool b, bool c) external {
        require(!revertOnPolicy, "policy disabled");
        require(msg.sender == collection, "caller must be collection");
        Policy storage p = policies[collection];
        p.level = level;
        p.disableAuthorizationMode = a;
        p.disableWildcardOperators = b;
        p.enableAccountFreezingMode = c;
        p.policyCalls += 1;
    }

    function applyListToCollection(address collection, uint120 id) external {
        require(!revertOnPolicy, "policy disabled");
        require(msg.sender == collection, "caller must be collection");
        policies[collection].listId = id;
    }

    function setTokenTypeOfCollection(address collection, uint16 tokenType) external {
        policies[collection].tokenType = tokenType;
    }

    function validateTransfer(address caller, address, address, uint256) external view {
        require(!blockedOperator[caller], "operator blocked");
    }
}

/// @dev Receiver that rejects ETH.
contract RejectingReceiver {
    receive() external payable {
        revert("no");
    }
}

/// @dev Attempts to re-enter the distributor's claim from its ETH receive hook.
contract ReentrantClaimer {
    address public target;
    address public asset;
    uint256[] public ids;
    bool public reentered;
    bool public reentryFailed;

    function arm(address target_, address asset_, uint256[] memory ids_) external {
        target = target_;
        asset = asset_;
        ids = ids_;
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            (bool ok,) = target.call(abi.encodeWithSignature("claim(address,uint256[])", asset, ids));
            reentryFailed = !ok;
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
