// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract FashionBoardFHE is SepoliaConfig {
    struct EncryptedStyle {
        uint256 id;
        euint32 encryptedStyleType;   // Encrypted style category
        euint32 encryptedColorPref;   // Encrypted color preference
        euint32 encryptedOccasion;    // Encrypted occasion type
        uint256 timestamp;
    }
    
    struct DecryptedStyle {
        string styleType;
        string colorPref;
        string occasion;
        bool isRevealed;
    }

    struct EncryptedProduct {
        euint32 encryptedProductId;
        euint32 encryptedMatchScore;
    }

    uint256 public styleCount;
    mapping(uint256 => EncryptedStyle) public encryptedStyles;
    mapping(uint256 => DecryptedStyle) public decryptedStyles;
    mapping(uint256 => EncryptedProduct[]) public styleRecommendations;
    
    mapping(string => euint32) private encryptedStyleTypeCount;
    string[] private styleTypeList;
    
    mapping(uint256 => uint256) private requestToStyleId;
    
    event StyleSubmitted(uint256 indexed id, uint256 timestamp);
    event RecommendationAdded(uint256 indexed styleId, uint256 productCount);
    event DecryptionRequested(uint256 indexed id);
    event StyleDecrypted(uint256 indexed id);
    
    modifier onlyOwner(uint256 styleId) {
        _;
    }
    
    function submitEncryptedStyle(
        euint32 encryptedStyleType,
        euint32 encryptedColorPref,
        euint32 encryptedOccasion
    ) public {
        styleCount += 1;
        uint256 newId = styleCount;
        
        encryptedStyles[newId] = EncryptedStyle({
            id: newId,
            encryptedStyleType: encryptedStyleType,
            encryptedColorPref: encryptedColorPref,
            encryptedOccasion: encryptedOccasion,
            timestamp: block.timestamp
        });
        
        decryptedStyles[newId] = DecryptedStyle({
            styleType: "",
            colorPref: "",
            occasion: "",
            isRevealed: false
        });
        
        emit StyleSubmitted(newId, block.timestamp);
    }
    
    function addRecommendations(
        uint256 styleId,
        EncryptedProduct[] calldata products
    ) public {
        for (uint i = 0; i < products.length; i++) {
            styleRecommendations[styleId].push(products[i]);
        }
        emit RecommendationAdded(styleId, products.length);
    }
    
    function requestStyleDecryption(uint256 styleId) public onlyOwner(styleId) {
        EncryptedStyle storage style = encryptedStyles[styleId];
        require(!decryptedStyles[styleId].isRevealed, "Already decrypted");
        
        bytes32[] memory ciphertexts = new bytes32[](3);
        ciphertexts[0] = FHE.toBytes32(style.encryptedStyleType);
        ciphertexts[1] = FHE.toBytes32(style.encryptedColorPref);
        ciphertexts[2] = FHE.toBytes32(style.encryptedOccasion);
        
        uint256 reqId = FHE.requestDecryption(ciphertexts, this.decryptStyle.selector);
        requestToStyleId[reqId] = styleId;
        
        emit DecryptionRequested(styleId);
    }
    
    function decryptStyle(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        uint256 styleId = requestToStyleId[requestId];
        require(styleId != 0, "Invalid request");
        
        EncryptedStyle storage eStyle = encryptedStyles[styleId];
        DecryptedStyle storage dStyle = decryptedStyles[styleId];
        require(!dStyle.isRevealed, "Already decrypted");
        
        FHE.checkSignatures(requestId, cleartexts, proof);
        
        string[] memory results = abi.decode(cleartexts, (string[]));
        
        dStyle.styleType = results[0];
        dStyle.colorPref = results[1];
        dStyle.occasion = results[2];
        dStyle.isRevealed = true;
        
        if (FHE.isInitialized(encryptedStyleTypeCount[dStyle.styleType]) == false) {
            encryptedStyleTypeCount[dStyle.styleType] = FHE.asEuint32(0);
            styleTypeList.push(dStyle.styleType);
        }
        encryptedStyleTypeCount[dStyle.styleType] = FHE.add(
            encryptedStyleTypeCount[dStyle.styleType], 
            FHE.asEuint32(1)
        );
        
        emit StyleDecrypted(styleId);
    }
    
    function getDecryptedStyle(uint256 styleId) public view returns (
        string memory styleType,
        string memory colorPref,
        string memory occasion,
        bool isRevealed
    ) {
        DecryptedStyle storage s = decryptedStyles[styleId];
        return (s.styleType, s.colorPref, s.occasion, s.isRevealed);
    }
    
    function getRecommendationsCount(uint256 styleId) public view returns (uint256) {
        return styleRecommendations[styleId].length;
    }
    
    function requestStyleTypeCountDecryption(string memory styleType) public {
        euint32 count = encryptedStyleTypeCount[styleType];
        require(FHE.isInitialized(count), "Style type not found");
        
        bytes32[] memory ciphertexts = new bytes32[](1);
        ciphertexts[0] = FHE.toBytes32(count);
        
        uint256 reqId = FHE.requestDecryption(ciphertexts, this.decryptStyleTypeCount.selector);
        requestToStyleId[reqId] = bytes32ToUint(keccak256(abi.encodePacked(styleType)));
    }
    
    function decryptStyleTypeCount(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        uint256 styleTypeHash = requestToStyleId[requestId];
        string memory styleType = getStyleTypeFromHash(styleTypeHash);
        
        FHE.checkSignatures(requestId, cleartexts, proof);
        
        uint32 count = abi.decode(cleartexts, (uint32));
    }
    
    function bytes32ToUint(bytes32 b) private pure returns (uint256) {
        return uint256(b);
    }
    
    function getStyleTypeFromHash(uint256 hash) private view returns (string memory) {
        for (uint i = 0; i < styleTypeList.length; i++) {
            if (bytes32ToUint(keccak256(abi.encodePacked(styleTypeList[i]))) == hash) {
                return styleTypeList[i];
            }
        }
        revert("Style type not found");
    }
}