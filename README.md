---
title: Reserved Ownership Accounts
description: A registry for generating future-deployed smart contract accounts owned by users on external services
author: Paul Sullivan (@sullivph) <paul.sullivan@manifold.xyz>, Wilkins Chung (@wwchung) <wilkins@manifold.xyz>
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2023-04-25
requires: 1167, 1271
---

## Abstract

The following specifies a system for services to provide their users with a deterministic wallet address tied to identifying credentials (e.g. email address, phone number, etc.) without any blockchain interaction, and a mechanism to deploy and control a smart contract wallet (Account Instance) at the deterministic address in the future.

## Motivation

It is common for web services to allow their users to hold on-chain assets via custodial wallets. These wallets are typically EOAs, deployed smart contract wallets or omnibus contracts, with private keys or asset ownership information stored on a traditional database. This proposal outlines a solution that avoids the security concerns associated with historical approaches, and rids the need and implications of services controlling user assets

Users on external services that choose to leverage the following specification can be given an Ethereum address to receive assets without the need to do any on-chain transaction. These users can choose to attain control of said addresses at a future point in time. Thus, on-chain assets can be sent to and owned by a user beforehand, therefore enabling the formation of an on-chain identity without requiring the user to interact with the underlying blockchain.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

The system for creating deferred custody accounts consists of:

1. An Account Registry which provides a deterministic smart contract address for an external service based on an identifying salt, and a signature verified function that allows for the deployment and control of Account Instances by the end user
2. Account Instances created by the Account Registry for the end user which allow access to the assets received at the deterministic address prior to Account Instance deployment.

External services wishing to provide their users with reserved ownership accounts MUST maintain a relationship between a user's identifying credentials and a salt. The external service SHALL refer to an Account Registry Instance to retrieve the deterministic account address for a given salt. Users from a given service MUST be able to create an Account Instance by validating their identifying credentials via the external service, which SHOULD give the user a valid signature for their salt. Users SHALL pass this signature to the service's Account Registry Instance in a call to `createAccount` to create an Account Instance at the deterministic address.

### Account Registry
The Account Registry MUST implement the following interface:

```solidity
interface IAccountRegistry {
    /**
     * @dev Registry instances emit the AccountCreated event upon successful account creation
     */
    event AccountCreated(
        address account,
        address implementation,
        uint256 salt
    );

    /**
     * @dev Registry instances emit the AccountAssigned event upon successful account assignment
     */
    event AccountAssigned(address account, address owner);

    /**
     * @dev Creates a smart contract account.
     *
     * If account has already been created, returns the account address without calling create2.
     *
     * @param salt       - The identifying salt for which the user wishes to deploy an Account Instance
     *
     * Emits AccountCreated event
     * @return the address for which the Account Instance was created
     */
    function createAccount(uint256 salt) external returns (address);

    /**
     * @dev Assigns a smart contract account to a given owner.
     *
     * If the account has not already been created, the account will be created first using `createAccount`
     *
     * @param owner      - The initial owner of the new Account Instance
     * @param salt       - The identifying salt for which the user wishes to deploy an Account Instance
     * @param expiration - If expiration > 0, represents expiration time for the signature.  Otherwise
     *                     signature does not expire.
     * @param message    - The keccak256 message which validates the owner, salt, expiration
     * @param signature  - The signature which validates the owner, salt, expiration
     * @param initData   - If initData is not empty and account has not yet been created, calls account with
     *                     provided initData after creation.
     *
     * Emits AccountAssigned event
     * @return the address to which the Account Instance was assigned
     */
    function assignAccount(
        address owner,
        uint256 salt,
        uint256 expiration,
        bytes32 message,
        bytes calldata signature,
        bytes calldata initData
    ) external returns (address);

    /**
     * @dev Returns the computed address of a smart contract account for a given identifying salt
     *
     * @return the computed address of the account
     */ 
    function account(uint256 salt) external view returns (address);
}
```

- The Account Registry MUST use an immutable account implementation address.
- `assignAccount` SHOULD verify that the msg.sender has permission to deploy the Account Instance for the identifying salt and initial owner. Verification SHOULD be done by validating the message and signature against the owner, salt and expiration using ECDSA for EOA signers, or EIP-1271 for smart contract signers
- `assignAccount` SHOULD verify that the block.timestamp < expiration or that expiration == 0
- New accounts SHOULD be deployed as [EIP-1167](https://eips.ethereum.org/EIPS/eip-1167) proxies and ownership SHOULD be assigned to the initial owner


### Account Instance
The Account Instance can be any smart contract wallet implementation.

- All Account Instances MUST be created using an Account Registry Instance
- Account Instance SHOULD support [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271)
- Account Instance SHOULD provide access to assets previously sent to the address at which the Account Instance is deployed to


## Rationale

### Service-Owned Registry Instances

While it might seem more user-friendly to implement and deploy a universal registry for reserved ownership accounts, we believe that it is important for external service providers to have the option to own and control their own Account Registry.  This provides the flexibility of implementing their own permission controls and account deployment authorization frameworks.

We are providing a reference Registry Factory which can deploy Account Registries for an external service, which comes with:
- Immutable Account Instance implementation
- Validation for the `assignAccount` method via ECDSA for EOA signers, or ERC-1271 validation for smart contract signers
- Ability for the Account Registry deployer to change the signing addressed used for `assignAccount` validation

### Account Registry and Account Implementation Coupling

Since Account Instances are deployed as [ERC-1167](https://eips.ethereum.org/EIPS/eip-1167) proxies, the account implementation address affects the addresses of accounts deployed from a given Account Registry. Requiring that registry instances be linked to a single, immutable account implementation ensures consistency between a user's salt and linked address on a given Account Registry Instance.

This also allows services to gain the the trust of users by deploying their registries with a reference to a trusted account implementation address.

Furthermore, account implementations can be designed as upgradeable, so users are not necessarily bound to the implementation specified by the Account Registry Instance used to create their account.

## Reference Implementation

The following is an example of an Account Registry Factory which can be used by external service providers to deploy their own Account Registry Instance.

### Account Registry Factory

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @author: manifold.xyz

import {Create2} from "openzeppelin/utils/Create2.sol";

import {Address} from "../../lib/Address.sol";
import {ERC1167ProxyBytecode} from "../../lib/ERC1167ProxyBytecode.sol";
import {IAccountRegistryFactory} from "./IAccountRegistryFactory.sol";

contract AccountRegistryFactory is IAccountRegistryFactory {
    using Address for address;

    error InitializationFailed();

    address private immutable registryImplementation = 0x076B08EDE2B28fab0c1886F029cD6d02C8fF0E94;

    function createRegistry(address implementation, uint96 index) external returns (address) {
        bytes32 salt = _getSalt(msg.sender, index);
        bytes memory code = ERC1167ProxyBytecode.createCode(registryImplementation);
        address _registry = Create2.computeAddress(salt, keccak256(code));

        if (_registry.isDeployed()) return _registry;

        _registry = Create2.deploy(0, salt, code);

        (bool success, ) = _registry.call(
            abi.encodeWithSignature("initialize(address,address)", implementation, msg.sender)
        );
        if (!success) revert InitializationFailed();

        emit AccountRegistryCreated(_registry, implementation, index);

        return _registry;
    }

    function registry(address deployer, uint96 index) external view override returns (address) {
        bytes32 salt = _getSalt(deployer, index);
        bytes memory code = ERC1167ProxyBytecode.createCode(registryImplementation);
        return Create2.computeAddress(salt, keccak256(code));
    }

    function _getSalt(address deployer, uint96 index) private pure returns (bytes32) {
        return bytes32(abi.encodePacked(deployer, index));
    }
}
```

### Account Registry

```solidity
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

    constructor() {
        _disableInitializers();
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
```

### Example Account Implementation

```solidity
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

/// @author: manifold.xyz

import {IERC1271} from "openzeppelin/interfaces/IERC1271.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";
import {ERC165Checker} from "openzeppelin/utils/introspection/ERC165Checker.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";
import {Initializable} from "openzeppelin/proxy/utils/Initializable.sol";

import {IERC1967Account} from "./IERC1967Account.sol";

/**
 * @title ERC1967AccountImplementation
 * @notice A lightweight, upgradeable smart contract wallet implementation
 */
contract ERC1967AccountImplementation is
    IERC165,
    IERC721Receiver,
    IERC1155Receiver,
    IERC1967Account,
    IERC1271,
    Initializable
{
    address public owner;

    constructor() {
        _disableInitializers();
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    function initialize(address owner_) external {
        require(owner == address(0), "Already initialized");
        owner = owner_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return (interfaceId == type(IERC1967Account).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev {See IAccount-executeCall}
     */
    function executeCall(
        address _target,
        uint256 _value,
        bytes calldata _data
    ) external payable override onlyOwner returns (bytes memory _result) {
        bool success;
        // solhint-disable-next-line avoid-low-level-calls
        (success, _result) = _target.call{value: _value}(_data);
        require(success, string(_result));
        emit TransactionExecuted(_target, _value, _data);
        return _result;
    }

    /**
     * @dev {See IAccount-setOwner}
     */
    function setOwner(address newOwner) external override onlyOwner {
        owner = newOwner;
    }

    receive() external payable {}

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        bool isValid = SignatureChecker.isValidSignatureNow(owner, hash, signature);
        if (isValid) {
            return IERC1271.isValidSignature.selector;
        }

        return "";
    }
}
```

## Security Considerations

### Front-running

Deployment of reserved ownership accounts through an Account Registry Instance through calls to `assignAccount` could be front-run by a malicious actor. However, if the malicious actor attempted to alter the `owner` parameter in the calldata, the Account Registry Instance would find the signature to be invalid, and revert the transaction. Thus, any successful front-running transaction would deploy an identical Account Instance to the original transaction, and the original owner would still gain control over the address.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
