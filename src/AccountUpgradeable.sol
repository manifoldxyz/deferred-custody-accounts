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

import {IAccount} from "./interfaces/IAccount.sol";

/**
 * @title AccountUpgradeable
 * @notice A lightweight smart contract wallet implementation
 */
contract AccountUpgradeable is IERC165, IERC721Receiver, IERC1155Receiver, IAccount, IERC1271 {
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    function initialize(address owner_) external {
        require(owner == address(0), "Already initialized");
        owner = owner_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return (interfaceId == type(IAccount).interfaceId ||
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

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view returns (bytes4 magicValue) {
        bool isValid = SignatureChecker.isValidSignatureNow(owner, hash, signature);
        if (isValid) {
            return IERC1271.isValidSignature.selector;
        }

        return "";
    }
}
