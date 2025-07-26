// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
  ░██████              ░██ ░██   ░██    ░██     ░██ ░██   ░██    
 ░██   ░██             ░██       ░██    ░██    ░██        ░██    
░██         ░████████  ░██ ░██░████████ ░██   ░██   ░██░████████ 
 ░████████  ░██    ░██ ░██ ░██   ░██    ░███████    ░██   ░██    
        ░██ ░██    ░██ ░██ ░██   ░██    ░██   ░██   ░██   ░██    
 ░██   ░██  ░███   ░██ ░██ ░██   ░██    ░██    ░██  ░██   ░██    
  ░██████   ░██░█████  ░██ ░██    ░████ ░██     ░██ ░██    ░████ 
            ░██                                                  
            ░██
*/

import { Base64 }           from "@openzeppelin/contracts/utils/Base64.sol";
import { ERC1155 }          from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { IERC721 }          from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver }  from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Strings }          from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Split ERC-721
 * @author Valerio Di Napoli
 * @notice This contract allows the fractionalization of an ERC721 NFT into multiple ERC1155 splits.
 * Using 1155 allows for an easier and more gas-efficient management of multiple splits.
 * @dev It implements the IERC721Receiver interface to handle the receipt of the NFT.
 * The contract:
 *  - allows the deployer to mint splits for an escrowed NFT and any address holding all the splits
 *    to burn them to redeem the NFT;
 *  - uses the Minimal Proxy pattern to reduce deployment costs and ensure that for each NFT being
 *    fractionalized, a new instance of the contract is created, allowing for unique state management
 *    per NFT.
 */
contract SplitERC721 is ERC1155, IERC721Receiver {

    using {Strings.toString}            for uint256;
    using {Strings.toString}            for uint24;
    using {Strings.toChecksumHexString} for address;

    // --------------------------- STRUCTS ---------------------------

    /**
     * @notice Struct to hold the data of the fractionalized NFT.
     * @dev The struct is packed to minimize storage costs: 
     * - totalSplits is a uint24, enough for 1 million splits;
     * - timestamps are stored as uint64, enough for 500+ years (until Jul 21 2554).
     * @param totalSplits Total number of splits created for the NFT.
     * @param escrowTimestamp Timestamp when the NFT was escrowed - zero if not escrowed.
     * @param redeemTimestamp Timestamp when the NFT was redeemed - zero if not redeemed.
     * @param tokenContract Address of the NFT contract.
     * @param tokenId ID of the NFT being fractionalized.
     */
    struct SplitNFT {
        // Slot 0
        uint24 totalSplits;
        uint64 escrowTimestamp;
        uint64 redeemTimestamp;
        // Slot 1
        address tokenContract;
        // Slot 2
        uint256 tokenId;
    }

    // -------------------------- CONSTANTS --------------------------

    /// @notice Minimum number of splits allowed: 2 splits -> 0.5% ownership per split
    uint24 public constant MIN_SPLITS = 2;

    /// @notice Maximum number of splits allowed: 1 million splits -> 1 PIP (0.0001%) ownership per split
    uint24 public constant MAX_SPLITS = 1e6;


    // ----------------------- STATE VARIABLES -----------------------

    // Storage slot: 0
    address public escrower; // Address that escrowed the NFT, ensuring that only the escrower can mint splits
    // Storage slots: 1, 2, 3
    SplitNFT public splitNFT;

    // ---------------------------- EVENTS ---------------------------

    /// @notice Emitted when an NFT is fractionalized into splits
    /// @param nftContract Address of the NFT contract being fractionalized
    /// @param tokenId ID of the NFT being fractionalized
    /// @param splits Number of splits created for the NFT
    event NFTFractionalized(
        address indexed nftContract,
        uint256 indexed tokenId,
        uint24 splits
    );

    /// @notice Emitted when an NFT is redeemed by burning all splits
    /// @param nftContract Address of the NFT contract being redeemed
    /// @param tokenId ID of the NFT being redeemed
    /// @param redeemer Address of the user redeeming the NFT
    event NFTRedeemed(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed redeemer
    );

    // --------------------------- ERRORS ----------------------------

    /// @notice Error codes for various operations in the contract
    /// @dev This enum is used to categorize errors for better readability and maintainability
    /// Each error corresponds to a specific operation or validation failure
    enum ErrorCode {
        AlreadySplit, // The NFT has already been split
        AlreadyEscrowed, // The NFT has already been escrowed in this contract
        AlreadyRedeemed, // The NFT has already been redeemed
        InvalidNFTContract, // The NFT contract is not a valid ERC721 contract
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

    // ------------------------- CONSTRUCTOR -------------------------

    /**
     * @dev Constructor irrelevant with MinimalProxy pattern, but required by ERC1155
     */
    constructor() ERC1155("") {}

    // -------------------------- FUNCTIONS --------------------------

    /**
     * @notice Returns the URI for the NFT's metadata by retrieving the token URI of the escrowed
     * NFT.
     * @dev The function uses a try-catch block to handle the case where the NFT contract does not
     * implement the tokenURI function, preventing a revert in such cases.
     * @param tokenId The ID of the NFT for which to retrieve the URI.
     * @return string The URI of the NFT's metadata, or an empty string if not available.
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        SplitNFT memory nft = splitNFT;
        try IERC721Metadata(nft.tokenContract).tokenURI(nft.tokenId) returns (
            string memory tokenURI
        ) {
            return tokenURI;
        } catch {
            return "";
        }
    }

    /**
     * @notice Returns the contract URI for the SplitERC721 contract.
     * @dev This function provides metadata about the contract, including its name, description
     * and image.
     * @return string The contract URI in JSON format, encoded in Base64.
     */
    function contractURI() public view returns (string memory) {
        // Split-specific collection metadata
        SplitNFT memory nft = splitNFT;
        bool redeemed = nft.redeemTimestamp != 0;
        return string(abi.encodePacked(
            'data:application/json;base64,',
            Base64.encode(bytes(abi.encodePacked(
                '{"name": "',
                redeemed ? '[REDEEMED] ': '',
                'Split of NFT #', nft.tokenId.toString(), '",',
                '"description": "Token ID ',
                    nft.tokenId.toString(),
                    ', from the collection at address ',
                    nft.tokenContract.toChecksumHexString(),
                    ', fractionalized into ',
                    nft.totalSplits.toString(),
                    ' splits. The original token',
                    redeemed
                        ? ' has been redeemed and all splits have been burnt.'
                        : ' is safely stored in a smart contract and can be redeemed by burning 100% of the splits.',
                    '",',
                '"image": "[URL]/split-logo.png"', // Example image URL, can be replaced with a state variable or function call
                '}'
            )))
        ));
    }

    /**
     * @notice Handles the receipt of an NFT by this contract. See IERC721Receiver for details.
     * @dev This function is called when an NFT is transferred to this contract.
     * It sets up the SplitNFT struct with the escrowed NFT data and ensures that the contract
     * can only escrow a single NFT.
     * @param operator The address that is transferring the NFT.
     * @param from The address from which the NFT is being transferred.
     * @param tokenId The ID of the NFT being transferred.
     * @param data Additional data with no specified format, sent in the call to this contract.
     * @return bytes4 The selector of this function, indicating successful receipt of the NFT.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        // The contract can only escrow a single NFT
        if (splitNFT.escrowTimestamp != 0) revert SplitERC721Error(ErrorCode.AlreadyEscrowed);
        SplitNFT memory newSplitNFT = SplitNFT({
            escrowTimestamp: uint64(block.timestamp),
            redeemTimestamp: 0, // Will be set when the NFT is redeemed
            totalSplits: 0, // Will be set in _mintSplits
            tokenContract: msg.sender,
            tokenId: tokenId
        });
        splitNFT = newSplitNFT;
        escrower = operator;
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Initializes the contract with the given number of splits for the escrowed NFT.
     * @dev This function is called to set up the initial state of the contract.
     * It checks that the NFT is escrowed in this contract and mints the splits.
     * @param splits The number of splits to create for the NFT.
     * @param recipient The address that will receive the minted splits.
     */
    function split(
        uint24 splits,
        address recipient
    ) external {
        // Ensure the caller is the same address that escrowed the NFT
        if(msg.sender != escrower) revert SplitERC721Error(ErrorCode.OnlyEscrower);
        // Ensure the recipient is not the zero address
        if (recipient == address(0)) revert SplitERC721Error(ErrorCode.InvalidRecipient);
        // Validate the number of splits
        if (splits < MIN_SPLITS || splits > MAX_SPLITS) revert InvalidNumberOfSplits(splits);
        // Read the splitNFT data from storage
        SplitNFT memory NFTData = splitNFT;
        // Ensure the NFT has not already been split
        if (NFTData.totalSplits != 0) revert SplitERC721Error(ErrorCode.AlreadySplit);
        // Ensure the NFT contract is a valid ERC721 contract
        require(
            IERC721(NFTData.tokenContract).supportsInterface(type(IERC721).interfaceId),
            SplitERC721Error(ErrorCode.InvalidNFTContract)
        );
        // Ensure that the NFT was transferred to this contract
        if (IERC721(NFTData.tokenContract).ownerOf(NFTData.tokenId) != address(this)) {
            revert NotEscrowed(NFTData.tokenContract, NFTData.tokenId);
        }
        // Mint the splits for the NFT
        splitNFT.totalSplits = splits;
        _mint(recipient, 0, splits, "");
        emit NFTFractionalized({
            nftContract: NFTData.tokenContract,
            tokenId: NFTData.tokenId,
            splits: splits
        });
    }

    /**
     * @notice Redeems the fractionalized NFT by burning all splits and transferring the original NFT
     * to the caller.
     * @dev The caller must own all splits of the NFT to redeem it.
     * @dev Emits an NFTRedeemed event upon successful redemption.
     */
    function redeem() external {
        SplitNFT memory NFTData = splitNFT; // Read the splitNFT data from storage
        // Ensure the NFT is escrowed and not already redeemed
        if (NFTData.escrowTimestamp == 0) revert NotEscrowed(NFTData.tokenContract, NFTData.tokenId);
        if (NFTData.redeemTimestamp != 0) revert SplitERC721Error(ErrorCode.AlreadyRedeemed);
        uint256 balance = balanceOf(msg.sender, 0);
        if (balance != NFTData.totalSplits) revert NotEnoughSplits(balance, NFTData.totalSplits);
        splitNFT.redeemTimestamp = uint64(block.timestamp);
        // Burn all the splits to redeem the NFT
        _burn(msg.sender, 0, NFTData.totalSplits);
        IERC721(NFTData.tokenContract).safeTransferFrom(address(this), msg.sender, NFTData.tokenId);
        emit NFTRedeemed({
            nftContract: NFTData.tokenContract,
            tokenId: NFTData.tokenId,
            redeemer: msg.sender
        });
    }

    /**
     * @notice Converts a number of splits to a percentage of the total splits.
     * @dev This function calculates the percentage of ownership represented by a given number of splits.
     * @param splits The number of splits to convert to a percentage.
     * @return uint256 The percentage of ownership represented by the given number of splits, in basis points (1/100th of a percent).
     */
    function ownershipFromSplits(uint24 splits) external view returns (uint256) {
        return (uint256(splits) * 10000) / splitNFT.totalSplits;
    }

    /**
     * @notice Checks if the contract supports a specific interface.
     * @dev This function overrides the supportsInterface function from ERC1155 to include
     * the IERC721Receiver interface.
     * @param interfaceId The interface identifier, as specified in ERC-165.
     * @return bool True if the contract implements the interface, false otherwise.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IERC721Receiver).interfaceId;
    }
}