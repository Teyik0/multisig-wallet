// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {MultiSig} from "../src/MultiSig.sol";

// forge coverage --report debug > report.log
contract MultiSigTest is Test {
    MultiSig public multiSig;

    address public constant USER1 = address(0x1);
    address public constant USER2 = address(0x2);
    address public constant USER3 = address(0x3);
    address public constant USER4 = address(0x4);
    address public constant USER5 = address(0x5);
    address public constant USER6 = address(0x6);

    function toDynamicArr(
        address[4] memory staticArray
    ) internal pure returns (address[] memory) {
        address[] memory dynamicArray = new address[](4);
        for (uint i = 0; i < 4; i++) {
            dynamicArray[i] = staticArray[i];
        }
        return dynamicArray;
    }

    function setUp() public {
        address[4] memory staticArray = [USER1, USER2, USER3, USER4];
        multiSig = new MultiSig(toDynamicArr(staticArray), 3);

        vm.deal(address(multiSig), 10 ether);

        vm.deal(USER1, 1 ether);
        vm.deal(USER2, 1 ether);
        vm.deal(USER3, 1 ether);
        vm.deal(USER4, 1 ether);
        vm.deal(USER5, 1 ether);
        vm.deal(USER6, 1 ether);
    }

    function test_constructor_failed_SignersRequired() public {
        address[] memory dynamicArray = new address[](1);
        dynamicArray[0] = USER1;
        vm.expectRevert(abi.encodeWithSignature("SignersRequired()"));
        multiSig = new MultiSig(dynamicArray, 1);
    }

    function test_constructor_failed_InvalidNumConfirmationsRequired() public {
        address[4] memory staticArray = [USER1, USER2, USER3, USER4];
        vm.expectRevert();
        multiSig = new MultiSig(toDynamicArr(staticArray), 1);
    }

    function test_constructor_failed_InvalidSigner() public {
        address[4] memory staticArray = [address(0), USER2, USER3, USER5];
        vm.expectRevert(
            abi.encodeWithSignature("InvalidSigner(address)", address(0))
        );
        multiSig = new MultiSig(toDynamicArr(staticArray), 3);
    }

    function test_constructor_failed_DuplicateSigner() public {
        address[4] memory staticArray = [USER1, USER1, USER3, USER5];
        vm.expectRevert(
            abi.encodeWithSignature("DuplicateSigner(address)", USER1)
        );
        multiSig = new MultiSig(toDynamicArr(staticArray), 3);
    }

    function test_submitTransaction() public {
        address to = address(0x4);
        uint value = 1 ether;
        bytes memory data = "0x";

        vm.startPrank(USER1);
        multiSig.submitTransaction(to, value, data);

        (
            address transactionTo,
            uint transactionValue,
            bytes memory transactionData,
            bool executed,
            uint numConfirmations
        ) = multiSig.getTransaction(0);

        assertEq(transactionTo, to, "Transaction 'to' address mismatch");
        assertEq(transactionValue, value, "Transaction value mismatch");
        assertEq(transactionData, data, "Transaction data mismatch");
        assertEq(executed, false, "Transaction should not be executed");
        assertEq(
            numConfirmations,
            1,
            "Transaction should have 1 confirmation initially"
        );
        vm.stopPrank();
    }

    function test_submitTransaction_failed_notASigner() public {
        address to = address(0x247);
        uint value = 1 ether;
        bytes memory data = "0x";

        vm.startPrank(USER5);
        vm.expectRevert(abi.encodeWithSignature("NotSigner()"));
        multiSig.submitTransaction(to, value, data);
        vm.stopPrank();
    }

    function test_confirmTransaction() public {
        address to = address(0x247);
        uint value = 1 ether;
        bytes memory data = "0x";

        vm.startPrank(USER1);
        multiSig.submitTransaction(to, value, data);
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmTransaction(0);
        vm.stopPrank();

        (, , , bool executed, uint numConfirmations) = multiSig.getTransaction(
            0
        );
        assertEq(
            numConfirmations,
            2,
            "Number of confirmations should be 2 after confirmation"
        );
        assertEq(executed, false, "Transaction has not been executed yet");
    }

    function test_executeTransaction_failed() public {
        vm.startPrank(USER1);
        multiSig.submitTransaction(address(0x244), 1 ether, "");
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmTransaction(0);
        vm.stopPrank();

        vm.startPrank(USER3);
        vm.deal(address(multiSig), 0 ether);
        vm.expectRevert(abi.encodeWithSignature("TxExecutionFailed()"));
        multiSig.confirmTransaction(0);
        vm.stopPrank();
    }

    function test_executeTransaction() public {
        address to = address(0x247);
        uint value = 1 ether;
        bytes memory data = "0x";

        vm.startPrank(USER1);
        multiSig.submitTransaction(to, value, data);
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmTransaction(0);
        vm.stopPrank();

        vm.startPrank(USER3);
        multiSig.confirmTransaction(0);
        vm.stopPrank();

        (, , , bool executed, uint numConfirmations) = multiSig.getTransaction(
            0
        );
        assertEq(
            numConfirmations,
            3,
            "Number of confirmations should be 3 after confirmation"
        );
        assertEq(executed, true, "Transaction has been executed");
    }

    function test_confirmTransaction_failed_notASigner() public {
        address to = address(0x247);
        uint value = 1 ether;
        bytes memory data = "0x";
        vm.startPrank(USER1);
        multiSig.submitTransaction(to, value, data);
        vm.stopPrank();

        vm.startPrank(USER5);
        vm.expectRevert(abi.encodeWithSignature("NotSigner()"));
        multiSig.confirmTransaction(0);
        vm.stopPrank();
    }

    function test_confirmTransaction_failed_txNotExist() public {
        vm.startPrank(USER1);
        uint txIndex = 999;
        uint txCount = multiSig.getTransactionCount();

        vm.expectRevert(
            abi.encodeWithSignature(
                "TxDoesNotExist(uint256,uint256)",
                txIndex,
                txCount
            )
        );

        multiSig.confirmTransaction(txIndex);
        vm.stopPrank();
    }

    function test_confirmTransaction_failed_txAlreadyExecuted() public {
        address to = address(0x247);
        uint value = 1 ether;
        bytes memory data = "0x";

        vm.startPrank(USER1);
        multiSig.submitTransaction(to, value, data);
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmTransaction(0);
        vm.stopPrank();

        vm.startPrank(USER3);
        multiSig.confirmTransaction(0);
        vm.stopPrank();

        vm.startPrank(USER4);
        vm.expectRevert(
            abi.encodeWithSignature("TxAlreadyExecuted(uint256)", 0)
        );
        multiSig.confirmTransaction(0);
        vm.stopPrank();
    }

    function test_confirmTransaction_failed_alreadyConfirmed() public {
        vm.startPrank(USER1);
        multiSig.submitTransaction(address(0x123), 100, "data");
        vm.expectRevert(
            abi.encodeWithSignature(
                "TxAlreadyConfirmed(uint256,address)",
                0,
                USER1
            )
        );
        multiSig.confirmTransaction(0);
        vm.stopPrank();
    }

    function test_revokeConfirmation() public {
        vm.startPrank(USER1);
        multiSig.submitTransaction(address(0x123), 100, "data");
        multiSig.revokeConfirmation(0);

        (
            address to,
            uint value,
            ,
            bool executed,
            uint numConfirmations
        ) = multiSig.getTransaction(0);
        assertEq(numConfirmations, 0);
        assertEq(executed, false);
        assertEq(to, address(0x123));
        assertEq(value, 100);
        vm.stopPrank();
    }

    function test_revokeConfirmation_failed_notASigner() public {
        vm.startPrank(USER1);
        multiSig.submitTransaction(address(0x123), 100, "data");
        vm.stopPrank();

        vm.startPrank(USER5);
        uint txIndex = multiSig.getTransactionCount() - 1;
        vm.expectRevert(abi.encodeWithSignature("NotSigner()"));
        multiSig.revokeConfirmation(txIndex);

        vm.stopPrank();
    }

    function test_revokeConfirmation_TxNotConfirmed() public {
        vm.startPrank(USER1);
        multiSig.submitTransaction(address(0x123), 100, "data");
        vm.stopPrank();
        uint txIndex = multiSig.getTransactionCount() - 1;

        vm.startPrank(USER2);
        vm.expectRevert(
            abi.encodeWithSignature(
                "TxNotConfirmed(uint256,address)",
                txIndex,
                USER2
            )
        );
        multiSig.revokeConfirmation(txIndex);
        vm.stopPrank();
    }

    function test_revokeConfirmation_failed_txNotExist() public {
        vm.startPrank(USER1);
        uint nonExistentTxIndex = 999;
        vm.expectRevert(
            abi.encodeWithSignature(
                "TxDoesNotExist(uint256,uint256)",
                nonExistentTxIndex,
                multiSig.getTransactionCount()
            )
        );
        multiSig.revokeConfirmation(nonExistentTxIndex);
        vm.stopPrank();
    }

    function test_revokeConfirmation_failed_txAlreadyExecuted() public {
        vm.startPrank(USER1);
        multiSig.submitTransaction(address(0x123), 100, "data");
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmTransaction(0);
        vm.stopPrank();

        vm.startPrank(USER3);
        multiSig.confirmTransaction(0);

        uint txIndex = multiSig.getTransactionCount() - 1;
        vm.expectRevert(
            abi.encodeWithSignature("TxAlreadyExecuted(uint256)", txIndex)
        );
        multiSig.revokeConfirmation(txIndex);

        vm.stopPrank();
    }

    function test_getSigners() public view {
        address[] memory signers = multiSig.getSigners();
        assertEq(signers.length, 4);
        assertEq(signers[0], USER1);
        assertEq(signers[1], USER2);
        assertEq(signers[2], USER3);
        assertEq(signers[3], USER4);
    }

    function test_getTransactionCount() public {
        vm.startPrank(USER1);
        multiSig.submitTransaction(address(0x123), 100, "data");
        multiSig.submitTransaction(address(0x123), 100, "data");
        multiSig.submitTransaction(address(0x123), 100, "data");
        vm.stopPrank();

        assertEq(multiSig.getTransactionCount(), 3);
    }

    function test_submitAddSignerRequest() public {
        vm.startPrank(USER1);
        multiSig.submitSignerRequest(USER5, true);
        vm.stopPrank();
        MultiSig.SignerRequest memory request = multiSig.getSignerRequest(0);

        assertEq(multiSig.getSignerRequestsCount(), 1);
        assertEq(request.newSigner, USER5);
        assertEq(request.addOrRevoke, true);
        assertEq(request.executed, false);
        assertEq(request.numConfirmations, 1);
    }

    function test_submitSignerRequest_failed_InvalidAddress() public {
        vm.startPrank(USER1);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidSigner(address)", address(0))
        );
        multiSig.submitSignerRequest(address(0), true);
        vm.stopPrank();
    }

    function test_submitSignerRequest_failed_AlreadyASigner() public {
        vm.startPrank(USER1);
        vm.expectRevert(
            abi.encodeWithSignature("AlreadyASigner(address)", USER1)
        );
        multiSig.submitSignerRequest(USER1, true);
        vm.stopPrank();
    }

    function test_submitAddSignerRequest_failed_notASigner() public {
        vm.startPrank(USER5);
        vm.expectRevert(abi.encodeWithSignature("NotSigner()"));
        multiSig.submitSignerRequest(USER5, true);
        vm.stopPrank();
    }

    function test_confirmSignerRequest() public {
        vm.startPrank(USER1);
        multiSig.submitSignerRequest(USER5, true);
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmSignerRequest(0);
        vm.stopPrank();

        MultiSig.SignerRequest memory request = multiSig.getSignerRequest(0);
        assertEq(request.numConfirmations, 2);
        assertEq(request.executed, false);
        assertEq(request.newSigner, USER5);
    }

    function test_executeSignerRequest() public {
        vm.startPrank(USER1);
        multiSig.submitSignerRequest(USER5, true);
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmSignerRequest(0);
        vm.stopPrank();

        vm.startPrank(USER3);
        multiSig.confirmSignerRequest(0);
        vm.stopPrank();

        MultiSig.SignerRequest memory request = multiSig.getSignerRequest(0);
        address[] memory signers = multiSig.getSigners();
        assertEq(request.numConfirmations, 3);
        assertEq(request.executed, true);
        assertEq(request.newSigner, USER5);
        assertEq(signers.length, 5);
    }

    function test_executeRevokeSignerRequest() public {
        vm.startPrank(USER1);
        multiSig.submitSignerRequest(USER4, false);
        vm.stopPrank();

        vm.startPrank(USER2);
        multiSig.confirmSignerRequest(0);
        vm.stopPrank();

        vm.startPrank(USER3);
        multiSig.confirmSignerRequest(0);
        vm.stopPrank();
    }
}
