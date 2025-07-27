// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 *   ░██████              ░██ ░██   ░██    ░██     ░██ ░██   ░██
 *  ░██   ░██             ░██       ░██    ░██    ░██        ░██
 * ░██         ░████████  ░██ ░██░████████ ░██   ░██   ░██░████████
 *  ░████████  ░██    ░██ ░██ ░██   ░██    ░███████    ░██   ░██
 *         ░██ ░██    ░██ ░██ ░██   ░██    ░██   ░██   ░██   ░██
 *  ░██   ░██  ░███   ░██ ░██ ░██   ░██    ░██    ░██  ░██   ░██
 *   ░██████   ░██░█████  ░██ ░██    ░████ ░██     ░██ ░██    ░████
 *             ░██
 *             ░██
 */

/**
 * @title Split ERC-721 Errors
 * @author Valerio Di Napoli
 * @notice Defines custom errors for the Split ERC-721 fractionalization system.
 */
interface ISplitERC721Errors {
    /// @notice Error codes for various operations in the contract
    /// @dev This enum is used to categorize errors for better readability and maintainability
    /// Each error corresponds to a specific operation or validation failure
    enum ErrorCode {
        AlreadySplit, // The NFT has already been split
        AlreadyEscrowed, // The NFT has already been escrowed in this contract
        AlreadyRedeemed, // The NFT has already been redeemed
        OnlyEscrower, // Caller is not the address that escrowed the NFT
        InvalidRecipient // The recipient address is invalid (zero address)

    }

    /// @notice Used for errors with no arguments (optimizes bytecode size and improves readability)
    error SplitERC721Error(ErrorCode code);

    /// @notice Emitted when NFT being fractionalized is not escrowed in this contract
    error NotEscrowed(address nftContract, uint256 tokenId);

    /// @notice Emitted when the number of splits is less than the minimum or greater than the maximum allowed
    error InvalidNumberOfSplits(uint256 splits);

    /// @notice Emitted when caller does not own enough splits to perform an action
    error NotEnoughSplits(uint256 owned, uint256 required);
}
