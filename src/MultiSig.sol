// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {console} from "forge-std/Test.sol";

error NotSigner();
error TxDoesNotExist(uint256 txIndex, uint256 transactionsLength);
error TxAlreadyExecuted(uint256 txIndex);
error TxAlreadyConfirmed(uint256 txIndex, address signer);

error SignersRequired();
error InvalidNumConfirmationsRequired(uint256 provided, uint256 totalSigners);
error InvalidSigner(address signer);
error DuplicateSigner(address signer);

error NotEnoughConfirmations(
    uint256 numConfirmations,
    uint256 requiredConfirmations
);
error TxExecutionFailed();

error TxNotConfirmed(uint256 txIndex, address signer);

error AlreadyASigner(address signer);
error MaxSignersExceeded();

contract MultiSig {
    event Deposit(address indexed sender, uint amount, uint balance);
    event SubmitTransaction(
        address indexed signer,
        uint indexed txIndex,
        address indexed to,
        uint value,
        bytes data
    );
    event ConfirmTransaction(address indexed signer, uint indexed txIndex);
    event RevokeConfirmation(address indexed signer, uint indexed txIndex);
    event ExecuteTransaction(address indexed signer, uint indexed txIndex);

    address[] public signers;

    mapping(address => bool) public isSigner;

    uint public numConfirmationsRequired;
    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
        uint numConfirmations;
    }

    // mapping from tx index => signer => bool
    // this verify if a tx has been confirmed by a signer
    mapping(uint => mapping(address => bool)) public isConfirmed;

    Transaction[] public transactions;

    modifier onlySigner() {
        if (!isSigner[msg.sender]) {
            revert NotSigner();
        }
        _;
    }

    modifier txExists(uint _txIndex) {
        if (_txIndex >= transactions.length) {
            revert TxDoesNotExist(_txIndex, transactions.length);
        }
        _;
    }

    modifier notExecuted(uint _txIndex) {
        if (transactions[_txIndex].executed) {
            revert TxAlreadyExecuted(_txIndex);
        }
        _;
    }

    modifier notConfirmed(uint _txIndex) {
        if (isConfirmed[_txIndex][msg.sender]) {
            revert TxAlreadyConfirmed(_txIndex, msg.sender);
        }
        _;
    }

    constructor(address[] memory _signers, uint _numConfirmationRequired) {
        if (_signers.length < 2) {
            // 2 signers minimum
            revert SignersRequired();
        }

        if (
            _numConfirmationRequired < 2 || // 2 signers minimum on each tx
            _numConfirmationRequired > _signers.length
        ) {
            revert InvalidNumConfirmationsRequired(
                _numConfirmationRequired,
                _signers.length
            );
        }

        for (uint i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            if (signer == address(0)) {
                revert InvalidSigner(signer);
            }
            if (isSigner[signer]) {
                revert DuplicateSigner(signer);
            }
            isSigner[signer] = true;
            signers.push(signer);
        }

        numConfirmationsRequired = _numConfirmationRequired;
    }

    function submitTransaction(
        address _to,
        uint _value,
        bytes memory _data
    ) public onlySigner {
        uint txIndex = transactions.length;
        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                numConfirmations: 1 // 1 correspond to the submitter of the tx
            })
        );
        isConfirmed[txIndex][msg.sender] = true;
        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    function confirmTransaction(
        uint _txIndex
    )
        public
        onlySigner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;
        emit ConfirmTransaction(msg.sender, _txIndex);

        if (transaction.numConfirmations >= numConfirmationsRequired) {
            _executeTransaction(_txIndex);
        }
    }

    function _executeTransaction(uint _txIndex) private {
        Transaction storage transaction = transactions[_txIndex];
        transaction.executed = true;

        (bool success, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        if (!success) {
            revert TxExecutionFailed();
        }
        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeConfirmation(
        uint _txIndex
    ) public onlySigner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];

        if (!isConfirmed[_txIndex][msg.sender]) {
            revert TxNotConfirmed(_txIndex, msg.sender);
        }

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function getSigners() public view returns (address[] memory) {
        return signers;
    }

    function getTransactionCount() public view returns (uint) {
        return transactions.length;
    }

    function getTransaction(
        uint _txIndex
    )
        public
        view
        returns (
            address to,
            uint value,
            bytes memory data,
            bool executed,
            uint numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txIndex];
        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    event AddSignerRequestSubmitted(uint indexed requestId, address newSigner);
    event AddSignerRequestConfirmed(
        address indexed signer,
        uint indexed requestId
    );
    event AddSignerRequestExecuted(address indexed newSigner);
    event RevokeSignerRequestExecuted(address indexed newSigner);

    // mapping from tx new signer index => signer => bool
    // this verify if a tx new singer has been confirmed by a signer
    mapping(uint => mapping(address => bool)) public isNewSignerConfirmed;

    struct SignerRequest {
        address newSigner;
        uint numConfirmations;
        bool executed;
        bool addOrRevoke; // true pour ajouter, false pour retirer
    }
    SignerRequest[] public signerRequests;

    function submitSignerRequest(
        address _newSigner,
        bool addOrRevoke
    ) public onlySigner {
        if (_newSigner == address(0)) {
            revert InvalidSigner(_newSigner);
        }

        uint requestId = signerRequests.length;
        if (addOrRevoke) {
            if (isSigner[_newSigner]) {
                revert AlreadyASigner(_newSigner);
            }
            signerRequests.push(
                SignerRequest({
                    newSigner: _newSigner,
                    numConfirmations: 1,
                    executed: false,
                    addOrRevoke: true
                })
            );
        } else {
            if (!isSigner[_newSigner] && !addOrRevoke) {
                revert InvalidSigner(_newSigner);
            }
            if (signers.length == 2) {
                revert("Cannot remove signer, minimum 2 signers required");
            }
            signerRequests.push(
                SignerRequest({
                    newSigner: _newSigner,
                    numConfirmations: 1,
                    executed: false,
                    addOrRevoke: false
                })
            );
        }

        emit AddSignerRequestSubmitted(requestId, _newSigner);
    }

    function confirmSignerRequest(uint _requestId) public onlySigner {
        if (_requestId >= signerRequests.length) {
            revert TxDoesNotExist(_requestId, signerRequests.length);
        }

        SignerRequest storage request = signerRequests[_requestId];

        if (request.executed) {
            revert TxAlreadyExecuted(_requestId);
        }
        if (isNewSignerConfirmed[_requestId][msg.sender]) {
            revert TxAlreadyConfirmed(_requestId, msg.sender);
        }

        isNewSignerConfirmed[_requestId][msg.sender] = true;
        request.numConfirmations += 1;

        emit AddSignerRequestConfirmed(msg.sender, _requestId);

        if (request.numConfirmations >= numConfirmationsRequired) {
            if (request.addOrRevoke) {
                _executeAddSignerRequest(request);
            } else {
                _executeRevokeSignerRequest(request);
            }
        }
    }

    function _executeAddSignerRequest(SignerRequest storage request) private {
        isSigner[request.newSigner] = true;
        signers.push(request.newSigner);

        request.executed = true;

        emit AddSignerRequestExecuted(request.newSigner);
    }

    function _executeRevokeSignerRequest(SignerRequest memory request) private {
        uint signerIndex = signerIndexOf(request.newSigner);

        signers[signerIndex] = signers[signers.length - 1];
        signers.pop();

        isSigner[request.newSigner] = false;

        request.executed = true;

        emit RevokeSignerRequestExecuted(request.newSigner);
    }

    function signerIndexOf(address _signer) internal view returns (uint) {
        for (uint i = 0; i < signers.length; i++) {
            if (signers[i] == _signer) {
                return i;
            }
        }
        revert("Signer not found");
    }

    function getSignerRequestsCount() public view returns (uint) {
        return signerRequests.length;
    }

    function getSignerRequest(
        uint _requestId
    ) public view returns (SignerRequest memory) {
        return signerRequests[_requestId];
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
}
