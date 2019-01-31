pragma solidity 0.5.0;

import './Token.sol';


interface TokenConverter {

    function convert(
        Token _fromToken,
        Token _toToken,
        uint256 _fromAmount,
        uint256 _minReturn
    ) external payable returns (uint256 amount);

    function getReturn(
        Token _fromToken,
        Token _toToken,
        uint256 _fromAmount
    ) external view returns (uint256 amount);

}