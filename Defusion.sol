// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ERCNEXT.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IGradientGenerator.sol";

contract Defusion is ERCNEXT {
    IGradientGenerator public generator;

    error TransferFailed();

    constructor(address generatorAddress) ERCNEXT("Defusion", "DFUSE")  {
        generator = IGradientGenerator(generatorAddress);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return generator.tokenURI(tokenId, Strings.toString(
            uint256(
                keccak256(
                    abi.encodePacked(tokenId)
                )
            )
        ));
    }

    function setGenerator(address generatorAddress) public onlyOwner {
        generator = IGradientGenerator(generatorAddress);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        _setAutomatedMarketMakerPair(pair, value);
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }
}