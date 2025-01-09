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

/**
 * @title MultiSig
 * @dev A multi-signature wallet contract that requires multiple confirmations for transactions.
 */
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

    /**
     * @dev Modifier to check if the caller is a signer.
     */
    modifier onlySigner() {
        if (!isSigner[msg.sender]) {
            revert NotSigner();
        }
        _;
    }

    /**
     * @dev Modifier to check if a transaction exists.
     * @param _txIndex The index of the transaction.
     */
    modifier txExists(uint _txIndex) {
        if (_txIndex >= transactions.length) {
            revert TxDoesNotExist(_txIndex, transactions.length);
        }
        _;
    }

    /**
     * @dev Modifier to check if a transaction is not executed.
     * @param _txIndex The index of the transaction.
     */
    modifier notExecuted(uint _txIndex) {
        if (transactions[_txIndex].executed) {
            revert TxAlreadyExecuted(_txIndex);
        }
        _;
    }

    /**
     * @dev Modifier to check if a transaction is not confirmed by the caller.
     * @param _txIndex The index of the transaction.
     */
    modifier notConfirmed(uint _txIndex) {
        if (isConfirmed[_txIndex][msg.sender]) {
            revert TxAlreadyConfirmed(_txIndex, msg.sender);
        }
        _;
    }

    /**
     * @dev Constructor to initialize the contract with signers and the number of confirmations required.
     * @param _signers The addresses of the signers.
     * @param _numConfirmationRequired The number of confirmations required for a transaction.
     */
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

    /**
     * @dev Submits a transaction to be confirmed by the signers.
     * @param _to The address to send the transaction to.
     * @param _value The value of the transaction.
     * @param _data The data of the transaction.
     */
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

    /**
     * @dev Confirms a transaction.
     * @param _txIndex The index of the transaction to confirm.
     */
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

    /**
     * @dev Executes a confirmed transaction.
     * @param _txIndex The index of the transaction to execute.
     */
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

    /**
     * @dev Revokes a confirmation for a transaction.
     * @param _txIndex The index of the transaction to revoke confirmation for.
     */
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

    /**
     * @dev Returns the list of signers.
     * @return The list of signers.
     */
    function getSigners() public view returns (address[] memory) {
        return signers;
    }

    /**
     * @dev Returns the number of transactions.
     * @return The number of transactions.
     */
    function getTransactionCount() public view returns (uint) {
        return transactions.length;
    }

    /**
     * @dev Returns the details of a transaction.
     * @param _txIndex The index of the transaction.
     * @return to The address the transaction is sent to.
     * @return value The amount of ether to send in the transaction.
     * @return data The data payload for the transaction.
     * @return executed Whether the transaction has been executed.
     * @return numConfirmations The number of confirmations for the transaction.
     */
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

    /**
     * @dev Submits a request to add or revoke a signer.
     * @param _newSigner The address of the new signer.
     * @param addOrRevoke True to add a signer, false to revoke a signer.
     */
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

    /**
     * @dev Confirms a signer request.
     * @param _requestId The index of the signer request to confirm.
     */
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

    /**
     * @dev Executes an add signer request.
     * @param request The signer request to execute.
     */
    function _executeAddSignerRequest(SignerRequest storage request) private {
        isSigner[request.newSigner] = true;
        signers.push(request.newSigner);

        request.executed = true;

        emit AddSignerRequestExecuted(request.newSigner);
    }

    /**
     * @dev Executes a revoke signer request.
     * @param request The signer request to execute.
     */
    function _executeRevokeSignerRequest(SignerRequest memory request) private {
        uint signerIndex = signerIndexOf(request.newSigner);

        signers[signerIndex] = signers[signers.length - 1];
        signers.pop();

        isSigner[request.newSigner] = false;

        request.executed = true;

        emit RevokeSignerRequestExecuted(request.newSigner);
    }

    /**
     * @dev Returns the index of a signer.
     * @param _signer The address of the signer.
     * @return The index of the signer.
     */
    function signerIndexOf(address _signer) internal view returns (uint) {
        for (uint i = 0; i < signers.length; i++) {
            if (signers[i] == _signer) {
                return i;
            }
        }
        revert("Signer not found");
    }

    /**
     * @dev Returns the number of signer requests.
     * @return The number of signer requests.
     */
    function getSignerRequestsCount() public view returns (uint) {
        return signerRequests.length;
    }

    /**
     * @dev Returns the details of a signer request.
     * @param _requestId The index of the signer request.
     * @return The details of the signer request.
     */
    function getSignerRequest(
        uint _requestId
    ) public view returns (SignerRequest memory) {
        return signerRequests[_requestId];
    }

    /**
     * @dev Fallback function to receive Ether.
     */
    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
}
