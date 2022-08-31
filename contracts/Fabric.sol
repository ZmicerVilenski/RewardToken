// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AutostakeToken.sol";

contract Fabric {
    uint256 public numContracts = 0;
    mapping(uint256 => AutostakeToken) public deployedContracts;
    event TokenCreated(
        address owner,
        address deployedAddress,
        address predictedAddress
    );

    /**
     * @notice Create new Autostake Token on deterministic address
     * @param _salt A set of bytes, selecting this parameter, you can calculate the desired deployment address
     * @param _name New Token name
     * @param _symbol New Token symbol
     * @param _txFeeAddress address for transactions fee
     */
    function createAutostakeToken(
        bytes32 _salt,
        string calldata _name,
        string calldata _symbol,
        address _txFeeAddress
    ) external returns (AutostakeToken) {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            _salt,
                            keccak256(
                                abi.encodePacked(
                                    type(AutostakeToken).creationCode,
                                    abi.encode(
                                        _name,
                                        _symbol,
                                        msg.sender,
                                        _txFeeAddress
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );

        AutostakeToken token = new AutostakeToken{salt: _salt}(
            _name,
            _symbol,
            msg.sender,
            _txFeeAddress
        );
        token.transferOwnership(msg.sender);
        deployedContracts[numContracts] = token;
        numContracts++;

        emit TokenCreated(msg.sender, address(token), predictedAddress);

        return token;
    }
}
