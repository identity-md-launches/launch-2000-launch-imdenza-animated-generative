// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwarmHistory} from "../src/SwarmHistory.sol";
import {IMDenzaField} from "../src/IMDenzaField.sol";
import {IMDenzaRenderer} from "../src/IMDenzaRenderer.sol";
import {IMDenza} from "../src/IMDenza.sol";
import {IMDenzaDistributor} from "../src/IMDenzaDistributor.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {MockERC20, MockERC721, MockTransferValidator} from "./mocks/Mocks.sol";

/// @dev Shared fixture: the real stack deployed through the script, with the brief's mainnet
///      addresses (IMD token, Art Blocks core, default transfer validator) etched with mocks.
abstract contract BaseTest is Test {
    address constant CONFIGURATOR = 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193;
    address constant VALIDATOR = 0x721C002B0059009a671D00aD1700c9748146cd1B;

    SwarmHistory swarm;
    IMDenzaField field;
    IMDenzaRenderer renderer;
    IMDenza nft;
    IMDenzaDistributor dist;
    MockERC20 imd; // etched at IMDenza.IMD_TOKEN_A
    MockERC721 artBlocks; // etched at IMDenza.ART_BLOCKS
    MockERC721 identity; // plain deployment, set through the configurator
    MockTransferValidator validator; // etched at VALIDATOR

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public virtual {
        vm.roll(20_000_000);
        vm.warp(1_760_000_000);
        vm.prevrandao(bytes32(uint256(0xabc)));

        // The default validator exists on mainnet before the launch; etch it first so the ERC721C
        // constructor registers the token type like it will on chain.
        vm.etch(VALIDATOR, address(new MockTransferValidator()).code);
        validator = MockTransferValidator(VALIDATOR);

        Deploy.Deployed memory d = new Deploy().deploy(Deploy.Config({configurator: CONFIGURATOR}));
        swarm = d.swarm;
        field = d.field;
        renderer = d.renderer;
        nft = d.nft;
        dist = nft.distributor();

        vm.etch(nft.IMD_TOKEN_A(), address(new MockERC20("Identity.md", "IMD", 18)).code);
        imd = MockERC20(nft.IMD_TOKEN_A());
        vm.etch(nft.ART_BLOCKS(), address(new MockERC721()).code);
        artBlocks = MockERC721(nft.ART_BLOCKS());
        identity = new MockERC721();
    }

    function _giveImd(address to, uint256 amount) internal {
        imd.mint(to, amount);
    }

    /// @dev Free claim through the IMD route for `who` (gives them 26 IMD first).
    function _claimImd(address who) internal returns (uint256 id) {
        _giveImd(who, 26 ether);
        vm.prank(who);
        id = nft.claimWithImd();
    }

    function _publicMint(address who) internal returns (uint256 id) {
        uint256 price = nft.mintPrice(address(imd));
        _giveImd(who, price);
        vm.startPrank(who);
        imd.approve(address(nft), price);
        id = nft.mint(address(imd));
        vm.stopPrank();
    }
}
