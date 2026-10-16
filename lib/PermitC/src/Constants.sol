// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @dev Minimal subset of Limit Break's PermitC `Constants.sol` (MIT) needed by
///      creator-token-standards' `ERC721C`. Only the token-type identifiers are
///      used by the vendored contracts; the full PermitC library is not needed.

/// @dev Token type identifier for ERC20 collections.
uint256 constant TOKEN_TYPE_ERC20 = 20;
/// @dev Token type identifier for ERC721 collections.
uint256 constant TOKEN_TYPE_ERC721 = 721;
/// @dev Token type identifier for ERC1155 collections.
uint256 constant TOKEN_TYPE_ERC1155 = 1155;
