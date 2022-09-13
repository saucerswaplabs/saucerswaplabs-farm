// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

import "./HederaTokenService.sol";

contract SafeHederaTokenService is HederaTokenService {

    function safeMintToken(address token, uint64 amount, bytes[] memory metadata) internal
    returns (int responseCode, uint64 newTotalSupply, int64[] memory serialNumbers) {

        (responseCode, newTotalSupply, serialNumbers) = HederaTokenService.mintToken(token, amount, metadata);

        require(responseCode == HederaResponseCodes.SUCCESS, "Safe mint failed!");
    }

    function safeAssociateTokens(address account, address[] memory tokens) internal {
        int responseCode;
        (responseCode) = HederaTokenService.associateTokens(account, tokens);
        require(responseCode == HederaResponseCodes.SUCCESS, "Safe multiple associations failed!");
    }

    function safeAssociateToken(address account, address token) internal {
        int responseCode;
        (responseCode) = HederaTokenService.associateToken(account, token);
        require(responseCode == HederaResponseCodes.SUCCESS, "Safe single association failed!");
    }

    function safeTransferToken(address token, address sender, address receiver, int64 amount) internal {
        int responseCode;
        (responseCode) = HederaTokenService.transferToken(token, sender, receiver, amount);
        require(responseCode == HederaResponseCodes.SUCCESS, "Safe token transfer failed!");
    }
}
