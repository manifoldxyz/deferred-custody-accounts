// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @author: manifold.xyz

import {Create2} from "openzeppelin/utils/Create2.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Initializable} from "openzeppelin/proxy/utils/Initializable.sol";
import {IERC1271} from "openzeppelin/interfaces/IERC1271.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";

import {Address} from "../../lib/Address.sol";
import {IAccountRegistry} from "../../interfaces/IAccountRegistry.sol";
import {ERC1167ProxyBytecode} from "../../lib/ERC1167ProxyBytecode.sol";

contract AccountRegistryImplementation is Ownable, Initializable, IAccountRegistry {
    using Address for address;
    using ECDSA for bytes32;

    struct Signer {
        address account;
        bool isContract;
    }

    error InitializationFailed();
    error Unauthorized();

    address public implementation;
    Signer private signer;

    constructor(address implementation_) Ownable() initializer {
        implementation = implementation_;
    }

    function initialize(address implementation_, address owner) external initializer {
        implementation = implementation_;
        _transferOwnership(owner);
    }

    /**
     * @dev See {IAccountRegistry-createAccount}
     */
    function createAccount(
        address owner,
        uint256 salt,
        uint256 expiration,
        bytes32 message,
        bytes calldata signature,
        bytes calldata initData
    ) external override returns (address) {
        _verify(owner, salt, expiration, message, signature);
        bytes memory code = ERC1167ProxyBytecode.createCode(implementation);
        address _account = Create2.computeAddress(bytes32(salt), keccak256(code));

        if (_account.isDeployed()) return _account;

        _account = Create2.deploy(0, bytes32(salt), code);

        if (initData.length != 0) {
            (bool success, ) = _account.call(initData);
            if (!success) revert InitializationFailed();
        }

        emit AccountCreated(_account, implementation, salt);

        return _account;
    }

    /**
     * @dev See {IAccountRegistry-account}
     */
    function account(uint256 salt) external view override returns (address) {
        bytes memory code = ERC1167ProxyBytecode.createCode(implementation);
        return Create2.computeAddress(bytes32(salt), keccak256(code));
    }

    function setSigner(address newSigner) external onlyOwner {
        uint32 signerSize;
        assembly {
            signerSize := extcodesize(newSigner)
        }
        signer.account = newSigner;
        signer.isContract = signerSize > 0;
    }

    function _verify(
        address owner,
        uint256 salt,
        uint256 expiration,
        bytes32 message,
        bytes calldata signature
    ) internal view {
        address signatureAccount;

        if (signer.isContract) {
            if (!SignatureChecker.isValidSignatureNow(signer.account, message, signature))
                revert Unauthorized();
        } else {
            signatureAccount = message.recover(signature);
        }

        bytes32 expectedMessage = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n84", owner, salt, expiration)
        );

        if (
            message != expectedMessage ||
            (!signer.isContract && signatureAccount != signer.account) ||
            (expiration != 0 && expiration < block.timestamp)
        ) revert Unauthorized();
    }
}
