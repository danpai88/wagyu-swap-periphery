pragma solidity >=0.5.0;

interface IWagyuMigrator {
    function migrate(address token, uint amountTokenMin, uint amountVLXMin, address to, uint deadline) external;
}
