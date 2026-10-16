// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SwarmHistory} from "../src/SwarmHistory.sol";
import {IMDenzaField} from "../src/IMDenzaField.sol";
import {IMDenzaRenderer} from "../src/IMDenzaRenderer.sol";
import {IMDenza} from "../src/IMDenza.sol";

/// @notice Reference deployment order. The IMD launch deploys the same contracts through its
///         factory with the manifest arguments listed in the README; this script only exists so the
///         order and wiring can be rehearsed and tested locally. It never reads the environment.
contract Deploy is Script {
    struct Config {
        address configurator; // launch owner: may set the Identity MD collection once
    }

    struct Deployed {
        SwarmHistory swarm;
        IMDenzaField field;
        IMDenzaRenderer renderer;
        IMDenza nft;
    }

    /// @notice Deploys everything in manifest order: SwarmHistory, IMDenzaField, IMDenzaRenderer, IMDenza.
    function deploy(Config memory cfg) public returns (Deployed memory d) {
        d.swarm = new SwarmHistory();
        d.field = new IMDenzaField();
        d.renderer = new IMDenzaRenderer(address(d.swarm), address(d.field));
        d.nft = new IMDenza(cfg.configurator, address(d.renderer), address(d.swarm));
    }

    /// @notice Local rehearsal entry point; `configurator` is passed explicitly.
    function run(address configurator) external returns (Deployed memory d) {
        vm.startBroadcast();
        d = deploy(Config({configurator: configurator}));
        vm.stopBroadcast();
    }
}
