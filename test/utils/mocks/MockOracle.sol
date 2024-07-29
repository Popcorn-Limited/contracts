contract MockOracle {
    uint256 public price;

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function getQuote(uint inAmount, address base, address quote) external view returns (uint) {
        return price == 0 ? inAmount : price;
    }
}