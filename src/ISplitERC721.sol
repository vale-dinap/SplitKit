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
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title Split ERC-721 Interface
 * @author Valerio Di Napoli
 * @notice Interface for the Split ERC-721 contract that enables fractionalization of ERC721 NFTs
 * into ERC-1155 splits.
 * @dev This interface defines the external ABI for interacting with fractionalized NFTs.
 *
 * External contracts, frontends, and backends should use this interface to:
 * - Check contract capabilities and state
 * - Call fractionalization and redemption functions
 * - Listen for fractionalization events
 * - Query split ownership and metadata
 *
 * The interface extends IERC1155 to ensure compatibility with NFT marketplaces and DeFi protocols
 * that expect standard ERC1155 functionality for trading and transferring splits.
 *
 * Key features:
 * - Split any ERC721 into multiple ERC1155 shares
 * - Redeem original NFT by burning 100% of splits
 */
interface ISplitERC721 is IERC1155 {
    // ---------------------------- EVENTS ---------------------------

    /// @notice Emitted when an NFT is fractionalized into splits
    /// @param nftContract Address of the NFT contract being fractionalized
    /// @param tokenId ID of the NFT being fractionalized
    /// @param splits Number of splits created for the NFT
    event NFTFractionalized(address indexed nftContract, uint256 indexed tokenId, uint24 splits);

    /// @notice Emitted when an NFT is redeemed by burning all splits
    /// @param nftContract Address of the NFT contract being redeemed
    /// @param tokenId ID of the NFT being redeemed
    /// @param redeemer Address of the user redeeming the NFT
    event NFTRedeemed(address indexed nftContract, uint256 indexed tokenId, address indexed redeemer);

    // -------------------------- CONSTANTS --------------------------

    /// @notice Minimum number of splits allowed: 2 splits -> 0.5% ownership per split
    function MIN_SPLITS() external view returns (uint24);

    /// @notice Maximum number of splits allowed: 1 million splits -> 1 PIP (0.0001%) ownership per split
    function MAX_SPLITS() external view returns (uint24);

    // ------------------------ CORE FUNCTIONS -----------------------

    /**
     * @notice Initializes the contract with the given number of splits for the escrowed NFT.
     * @dev This function is called to set up the initial state of the contract.
     * It checks that the NFT is escrowed in this contract and mints the splits.
     * @param splits The number of splits to create for the NFT.
     * @param recipient The address that will receive the minted splits.
     */
    function split(uint24 splits, address recipient) external;

    /**
     * @notice Redeems the fractionalized NFT by burning all splits and transferring the original NFT
     * to the caller.
     * @dev The caller must own all splits of the NFT to redeem it.
     * @dev Emits an NFTRedeemed event upon successful redemption.
     */
    function redeem() external;

    // ------------------------ VIEW FUNCTIONS -----------------------

    /// @notice Address that escrowed the NFT, ensuring that only the escrower can mint splits
    function escrower() external view returns (address);

    /**
     * @notice Get the data of the fractionalized NFT.
     * @return tokenContract Address of the NFT contract.
     * @return tokenId ID of the fractionalized NFT within its original contract.
     * @return totalSplits Total number of splits created for the NFT.
     * @return escrowTimestamp Timestamp when the NFT was escrowed - zero if not escrowed.
     * @return redeemTimestamp Timestamp when the NFT was redeemed - zero if not redeemed.
     */
    function splitNFT()
        external
        view
        returns (
            address tokenContract,
            uint256 tokenId,
            uint24 totalSplits,
            uint64 escrowTimestamp,
            uint64 redeemTimestamp
        );

    /**
     * @notice Returns the contract URI for the SplitERC721 contract.
     * @dev This function provides metadata about the contract, including its name, description
     * and image.
     * @return string The contract URI in JSON format, encoded in Base64.
     */
    function contractURI() external view returns (string memory);

    /**
     * @notice Converts a number of splits to a percentage of the total splits.
     * @dev This function calculates the percentage of ownership represented by a given number of splits.
     * @param splits The number of splits to convert to a percentage.
     * @return uint256 The percentage of ownership represented by the given number of splits, in basis points (1/100th of a percent).
     */
    function ownershipFromSplits(uint24 splits) external view returns (uint256);
}
