// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MultiSig} from "../src/MultiSig.sol";

contract CounterScript is Script {
    MultiSig public multiSig;

    function setUp() public {}

    function toDynamicArr(
        address[3] memory staticArray
    ) internal pure returns (address[] memory) {
        address[] memory dynamicArray = new address[](4);
        for (uint i = 0; i < 3; i++) {
            dynamicArray[i] = staticArray[i];
        }
        return dynamicArray;
    }

    function run() public {
        vm.startBroadcast();
        address[3] memory signers = [
            vm.envAddress("ADDRESS1"),
            vm.envAddress("ADDRESS2"),
            vm.envAddress("ADDRESS3")
        ];
        multiSig = new MultiSig(toDynamicArr(signers), 2);

        vm.stopBroadcast();
    }
}
