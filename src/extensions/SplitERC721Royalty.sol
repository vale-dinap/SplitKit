// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SplitERC721, ERC1155} from  "../SplitERC721.sol";
import {IERC2981, IERC165} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title SplitERC721Royalty
 * @author Vakhtanh Chikladze (the.vaho1337@gmail.com)
 * @notice SplitERC721 extension with customizable royalty for the escrower.
 * @dev This contract extends SplitERC721 and implements the IERC2981 royalty standard.
 *      It allows the escrower to set a custom royalty percentage (in basis points) per tokenId.
 *      If no custom royalty is set for a tokenId, a default royalty value is used.
 *      The royalty receiver is always the escrower address.
 */
contract SplitERC721Royalty is SplitERC721, IERC2981 {
    /**
     * @dev The denominator for royalty basis points (10000 = 100%)
     */
    uint16 public constant ROYALTY_BPS_DENOMINATOR = 10000;

    /**
     * @dev The default royalty in basis points (500 = 5%)
     */
    uint16 public royaltyDefaultBps = 500; // 5%

    /**
     * @dev Mapping from tokenId to custom royalty basis points.
     */
    mapping (uint256 tokenId => uint16) public royaltyBps;

    /**
     * @notice Sets a new royalty percentage (only escrower).
     * @dev Sets the royalty percentage (in basis points) for a specific tokenId.
     *      Only the escrower can call this function.
     *      If _royaltyBps is set to type(uint16).max, royalty for this tokenId is set to 0 (disabled).
     *      Otherwise, the value must not exceed ROYALTY_BPS_DENOMINATOR (10000 = 100%).
     * @param tokenId The tokenId for which to set the royalty.
     * @param _royaltyBps The royalty percentage in basis points.
     */
    function setRoyaltyBps(uint256 tokenId, uint16 _royaltyBps) public {
        if (msg.sender != escrower) revert SplitERC721Error(ErrorCode.OnlyEscrower);
        if (_royaltyBps == type(uint16).max) {
            royaltyBps[tokenId] = _royaltyBps;
            return;
        } else {
            require(_royaltyBps <= ROYALTY_BPS_DENOMINATOR, "Royalty too high");
            royaltyBps[tokenId] = _royaltyBps;
        }
    }

    /**
     * @notice Returns the royalty percentage for a given tokenId.
     * @dev Returns the royalty percentage (in basis points) for the specified tokenId.
     *      If the value is type(uint16).max, royalty is disabled (returns 0).
     *      If no custom value is set (0), returns the default royalty value.
     * @param tokenId The tokenId to query.
     * @return The royalty percentage in basis points for `tokenId`
     */
    function getRoyaltyBps(uint256 tokenId) public view returns (uint16) {
        uint16 bps = royaltyBps[tokenId];
        if (bps == type(uint16).max) {
            return 0;
        } else {
            return bps == 0 ? royaltyDefaultBps : bps;
        }
    }

    /**
     * @notice Returns the royalty receiver address and royalty amount for a sale.
     * @dev Always returns escrower and royaltyBps of salePrice.
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        receiver = escrower;
        uint16 bps = getRoyaltyBps(tokenId);
        royaltyAmount = (salePrice * bps) / ROYALTY_BPS_DENOMINATOR;
    }

    /**
     * @dev Override supportsInterface to declare support for IERC2981.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}