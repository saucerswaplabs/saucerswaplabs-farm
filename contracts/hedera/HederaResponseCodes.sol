// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.0;

abstract contract HederaResponseCodes {

    // Other response codes may be found in the hip-206 repository of hedera hashgraph: 
    // https://github.com/hashgraph/hedera-services/tree/master/test-clients/src/main/resource/contract/solidity/hip-206

    int32 internal constant UNKNOWN = 21; // The responding node has submitted the transaction to the network. Its final status is still unknown.
    int32 internal constant SUCCESS = 22; // The transaction succeeded
    
}
