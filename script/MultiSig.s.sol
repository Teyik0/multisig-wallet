// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MultiSig} from "../src/MultiSig.sol";

contract CounterScript is Script {
    MultiSig public multiSig;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // multiSig = new MultiSig();

        vm.stopBroadcast();
    }
}
