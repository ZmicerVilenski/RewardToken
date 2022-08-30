// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AutostakeToken.sol";

contract Fabric {
    uint256 numContracts = 0;
    mapping(uint256 => AutostakeToken) deployedContracts;
    event TokenCreated(address owner, address token);

    function createToken(
        string calldata _name,
        string calldata _symbol,
        address _txFeeAddress
    ) public returns (AutostakeToken) {
        AutostakeToken token = AutostakeToken(
            new AutostakeToken(_name, _symbol, msg.sender, _txFeeAddress)
        );
        deployedContracts[numContracts] = token;
        numContracts++;

        emit TokenCreated(msg.sender, address(token));

        return token;
    }
}

//////////////////////////////////////////////////////////////////////////////////////////////////
contract Factory {
    function createToken(
        string calldata _name,
        string calldata _symbol,
        address _txFeeAddress,
        bytes32 _salt
    ) public payable returns (address) {
        return
            address(
                new AutostakeToken{salt: _salt}(
                    _name,
                    _symbol,
                    msg.sender,
                    _txFeeAddress
                )
            );
    }
}

//////////////////////////////////////////////////////////////////////////////////////////////////
contract D {
    uint256 public x;

    constructor(uint256 a) {
        x = a;
    }
}

contract C {
    function createDSalted(bytes32 salt, uint256 arg) public {
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    type(D).creationCode,
                                    abi.encode(arg)
                                )
                            )
                        )
                    )
                )
            )
        );

        D d = new D{salt: salt}(arg);
        require(address(d) == predictedAddress);
    }
}
