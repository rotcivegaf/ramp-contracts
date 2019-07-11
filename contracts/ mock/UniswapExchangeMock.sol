pragma solidity 0.5.10;

interface IUniswapFactory {
    function getExchange(address token) external view returns (address);
}

contract UniswapFactoryMock is IUniswapFactory {
    address exchange;

    constructor(address _exchange) public {
        exchange = _exchange;
    }
    function getExchange(address token) external view returns (address){
        return exchange;
    }

}