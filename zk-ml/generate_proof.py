#!/usr/bin/env python3
"""
AURA Protocol - ZK-ML Risk Score Generator
Simulates risk score calculation from wallet history and generates ZK proof.
"""

import json
import hashlib
import os
import time
from typing import List, Dict, Tuple
from dataclasses import dataclass
import numpy as np

@dataclass
class WalletTransaction:
    """Represents a wallet transaction for risk analysis."""
    timestamp: int
    value: float
    is_depot: bool
    token_type: str
    contract_address: str = ""

@dataclass
class RiskMetrics:
    """Risk metrics calculated from wallet history."""
    overall_score: int  # 0-100
    transaction_frequency: float
    average_transaction_value: float
    depot_ratio: float
    token_diversity: float
    interaction_score: float

class RiskAnalyzer:
    """Analyzes wallet history to calculate risk scores."""
    
    def __init__(self):
        self.risk_weights = {
            'transaction_frequency': 0.25,
            'transaction_value': 0.20,
            'depot_ratio': 0.20,
            'token_diversity': 0.15,
            'interaction_score': 0.20
        }
    
    def analyze_wallet(self, transactions: List[WalletTransaction]) -> RiskMetrics:
        """Analyze wallet transactions and calculate risk metrics."""
        if not transactions:
            return RiskMetrics(50, 0, 0, 0, 0, 0)
        
        # Sort transactions by timestamp
        sorted_txs = sorted(transactions, key=lambda x: x.timestamp)
        
        # Calculate metrics
        tx_frequency = self._calculate_frequency(sorted_txs)
        avg_value = self._calculate_average_value(transactions)
        depot_ratio = self._calculate_depot_ratio(transactions)
        token_diversity = self._calculate_token_diversity(transactions)
        interaction_score = self._calculate_interaction_score(transactions)
        
        # Calculate overall risk score (0-100, higher = riskier)
        overall_score = self._calculate_overall_risk(
            tx_frequency, avg_value, depot_ratio, token_diversity, interaction_score
        )
        
        return RiskMetrics(
            overall_score=int(overall_score),
            transaction_frequency=tx_frequency,
            average_transaction_value=avg_value,
            depot_ratio=depot_ratio,
            token_diversity=token_diversity,
            interaction_score=interaction_score
        )
    
    def _calculate_frequency(self, transactions: List[WalletTransaction]) -> float:
        """Calculate transaction frequency (transactions per day)."""
        if len(transactions) < 2:
            return 0.0
        
        time_span = transactions[-1].timestamp - transactions[0].timestamp
        if time_span == 0:
            return float(len(transactions))
        
        days = time_span / (24 * 60 * 60)
        frequency = len(transactions) / max(days, 1)
        
        # Normalize to 0-1 range (assuming 10 tx/day is high)
        return min(frequency / 10.0, 1.0)
    
    def _calculate_average_value(self, transactions: List[WalletTransaction]) -> float:
        """Calculate average transaction value."""
        if not transactions:
            return 0.0
        
        total_value = sum(tx.value for tx in transactions)
        avg_value = total_value / len(transactions)
        
        # Normalize to 0-1 range (assuming 1 ETH is high)
        return min(avg_value / 1.0, 1.0)
    
    def _calculate_depot_ratio(self, transactions: List[WalletTransaction]) -> float:
        """Calculate ratio of depot vs withdrawal transactions."""
        if not transactions:
            return 0.0
        
        depot_count = sum(1 for tx in transactions if tx.is_depot)
        ratio = depot_count / len(transactions)
        
        # Higher depot ratio = lower risk (more stable)
        return 1.0 - ratio  # Invert for risk calculation
    
    def _calculate_token_diversity(self, transactions: List[WalletTransaction]) -> float:
        """Calculate token diversity score."""
        if not transactions:
            return 0.0
        
        unique_tokens = len(set(tx.token_type for tx in transactions))
        
        # Normalize to 0-1 range (assuming 5+ tokens is diverse)
        return min(unique_tokens / 5.0, 1.0)
    
    def _calculate_interaction_score(self, transactions: List[WalletTransaction]) -> float:
        """Calculate interaction score with DeFi protocols."""
        if not transactions:
            return 0.0
        
        # Count interactions with known DeFi contracts
        defi_contracts = {
            "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",  # Uniswap V2 Router
            "0xE592427A0AEce92De3Edee1F18E0157C05861564",  # Uniswap V3 Router
            "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F",  # SushiSwap Router
        }
        
        defi_interactions = sum(
            1 for tx in transactions 
            if tx.contract_address.lower() in [c.lower() for c in defi_contracts]
        )
        
        # Normalize to 0-1 range
        return min(defi_interactions / len(transactions), 1.0)
    
    def _calculate_overall_risk(
        self, 
        frequency: float, 
        avg_value: float, 
        depot_ratio: float, 
        token_diversity: float, 
        interaction_score: float
    ) -> float:
        """Calculate overall risk score (0-100)."""
        weighted_risk = (
            frequency * self.risk_weights['transaction_frequency'] +
            avg_value * self.risk_weights['transaction_value'] +
            depot_ratio * self.risk_weights['depot_ratio'] +
            token_diversity * self.risk_weights['token_diversity'] +
            interaction_score * self.risk_weights['interaction_score']
        )
        
        return weighted_risk * 100

class ZKProofGenerator:
    """Simulates ZK proof generation for risk scores."""
    
    def __init__(self):
        self.circuit_inputs = {}
    
    def generate_proof(
        self, 
        wallet_address: str, 
        risk_metrics: RiskMetrics
    ) -> Tuple[bytes, Dict]:
        """
        Generate ZK proof for risk score.
        
        In production, this would use actual ZK-SNARK libraries like:
        - ezkl for ML model privacy
        - circom + snarkjs for circuit generation
        
        For simulation, we create a deterministic proof based on inputs.
        """
        # Prepare circuit inputs
        public_inputs = [
            int(wallet_address, 16),  # Convert address to uint256
            risk_metrics.overall_score
        ]
        
        private_inputs = [
            risk_metrics.transaction_frequency,
            risk_metrics.average_transaction_value,
            risk_metrics.depot_ratio,
            risk_metrics.token_diversity,
            risk_metrics.interaction_score
        ]
        
        # Simulate proof generation using hash of inputs
        proof_data = self._simulate_proof_generation(
            wallet_address, public_inputs, private_inputs
        )
        
        # Create proof structure compatible with AuraVerifier
        proof = self._format_proof(proof_data)
        
        return proof, {
            "public_inputs": public_inputs,
            "private_inputs": private_inputs,
            "risk_metrics": risk_metrics
        }
    
    def _simulate_proof_generation(
        self, 
        wallet_address: str, 
        public_inputs: List[int], 
        private_inputs: List[float]
    ) -> str:
        """Simulate the ZK proof generation process."""
        # Create deterministic hash based on all inputs
        input_string = f"{wallet_address}_{public_inputs}_{private_inputs}"
        hash_value = hashlib.sha256(input_string.encode()).hexdigest()
        
        # Add some randomness (in real ZK, this would be the actual proof)
        timestamp = int(time.time())
        proof_hash = hashlib.sha256(f"{hash_value}_{timestamp}".encode()).hexdigest()
        
        return proof_hash
    
    def _format_proof(self, proof_data: str) -> bytes:
        """Format proof data for contract compatibility."""
        # Convert hex string to bytes
        proof_bytes = bytes.fromhex(proof_data)
        
        # Pad to minimum length (AuraVerifier expects non-empty proof)
        if len(proof_bytes) < 32:
            proof_bytes = proof_bytes + b'\x00' * (32 - len(proof_bytes))
        
        return proof_bytes

def generate_mock_transactions(wallet_address: str) -> List[WalletTransaction]:
    """Generate mock wallet transactions for testing."""
    transactions = []
    base_time = int(time.time()) - (30 * 24 * 60 * 60)  # 30 days ago
    
    # Generate 20-30 random transactions
    num_transactions = np.random.randint(20, 30)
    
    for i in range(num_transactions):
        timestamp = base_time + (i * (24 * 60 * 60))  # One transaction per day
        value = np.random.uniform(0.01, 2.0)  # 0.01 to 2 ETH
        is_depot = np.random.choice([True, False], p=[0.6, 0.4])
        token_type = np.random.choice(['ETH', 'USDC', 'DAI', 'WBTC', 'UNI'])
        
        tx = WalletTransaction(
            timestamp=int(timestamp),
            value=float(value),
            is_depot=is_depot,
            token_type=token_type,
            contract_address="0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D" if not is_depot else ""
        )
        transactions.append(tx)
    
    return transactions

def main():
    """Main function to demonstrate the proof generation process."""
    print("AURA Protocol - ZK-ML Risk Score Generator")
    print("=" * 50)
    
    # Example wallet address
    wallet_address = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
    
    print(f"\nAnalyzing wallet: {wallet_address}")
    
    # Generate mock transactions
    print("Generating mock wallet transactions...")
    transactions = generate_mock_transactions(wallet_address)
    print(f"Generated {len(transactions)} transactions")
    
    # Analyze risk
    print("\nCalculating risk metrics...")
    analyzer = RiskAnalyzer()
    risk_metrics = analyzer.analyze_wallet(transactions)
    
    print(f"\nRisk Analysis Results:")
    print(f"  Overall Risk Score: {risk_metrics.overall_score}/100")
    print(f"  Transaction Frequency: {risk_metrics.transaction_frequency:.2f}")
    print(f"  Average Transaction Value: {risk_metrics.average_transaction_value:.2f} ETH")
    print(f"  Depot Ratio: {risk_metrics.depot_ratio:.2f}")
    print(f"  Token Diversity: {risk_metrics.token_diversity:.2f}")
    print(f"  Interaction Score: {risk_metrics.interaction_score:.2f}")
    
    # Generate ZK proof
    print("\nGenerating ZK proof...")
    proof_generator = ZKProofGenerator()
    proof, proof_data = proof_generator.generate_proof(wallet_address, risk_metrics)
    
    print(f"\nZK Proof Generated:")
    print(f"  Proof Length: {len(proof)} bytes")
    print(f"  Public Inputs: {proof_data['public_inputs']}")
    print(f"  Risk Score (Public): {proof_data['public_inputs'][1]}")
    
    # Save results to file
    output = {
        "wallet_address": wallet_address,
        "risk_metrics": {
            "overall_score": risk_metrics.overall_score,
            "transaction_frequency": risk_metrics.transaction_frequency,
            "average_transaction_value": risk_metrics.average_transaction_value,
            "depot_ratio": risk_metrics.depot_ratio,
            "token_diversity": risk_metrics.token_diversity,
            "interaction_score": risk_metrics.interaction_score
        },
        "zk_proof": {
            "proof_hex": proof.hex(),
            "public_inputs": proof_data['public_inputs']
        }
    }
    
    # Get the directory where this script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_file = os.path.join(script_dir, "proof_output.json")
    
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    
    print(f"\nResults saved to {output_file}")
    
    # Print risk tier recommendation
    print(f"\nRisk Tier Recommendation:")
    if risk_metrics.overall_score <= 25:
        print("  Tier 1 (Low Risk): 90% LTV")
    elif risk_metrics.overall_score <= 50:
        print("  Tier 2 (Medium-Low Risk): 75% LTV")
    elif risk_metrics.overall_score <= 75:
        print("  Tier 3 (Medium-High Risk): 60% LTV")
    else:
        print("  Tier 4 (High Risk): 45% LTV")

if __name__ == "__main__":
    main()
