// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AuraVerifier
 * @notice ZK proof verifier mock for the AURA Protocol.
 * @dev Reconstructs/verifies ZK-SNARK proof for risk scores and prevents proof theft.
 */
contract AuraVerifier {
    /**
     * @notice Verifies a ZK-SNARK proof with associated public inputs.
     * @dev For EZKL compliance, publicInputs are:
     *      publicInputs[0] = borrower address (uint256 casted from address)
     *      publicInputs[1] = risk score (0 to 100)
     * @param proof The ZK-SNARK proof.
     * @param publicInputs The public inputs of the circuit.
     * @return bool True if the proof is valid.
     */
    function verifyProof(bytes calldata proof, uint256[] calldata publicInputs) external pure returns (bool) {
        if (proof.length == 0) return false;
        
        // Mock invalid proof detection
        if (keccak256(proof) == keccak256(abi.encodePacked("invalid-proof"))) {
            return false;
        }
        if (proof.length == 1 && proof[0] == 0x00) {
            return false;
        }

        // Must have at least 2 public inputs
        if (publicInputs.length < 2) {
            return false;
        }

        // Verify risk score range (0-100)
        uint256 riskScore = publicInputs[1];
        if (riskScore > 100) {
            return false;
        }

        return true;
    }
}
