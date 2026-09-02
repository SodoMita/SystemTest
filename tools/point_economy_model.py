class PointEconomyModel:
    def __init__(self):
        self.BASE_RATE = 1.0 
        
        # Actions defined by (Time, Risk, Leverage, Max_Uses_Per_Match)
        self.actions = {
            "Kill Enemy":           {"time": 3.0, "risk": 0.70, "leverage": 1.2, "limit": 4},
            "Beacon Pressure":      {"time": 1.6, "risk": 0.20, "leverage": 1.0, "limit": 20},
            "Objective (Find)":     {"time": 4.0, "risk": 0.40, "leverage": 1.5, "limit": 2},
            "Objective (Carry)":    {"time": 6.0, "risk": 0.85, "leverage": 2.0, "limit": 1},
            "Objective (Slot/Win)": {"time": 2.0, "risk": 0.90, "leverage": 3.0, "limit": 1},
            "Repair Node":          {"time": 2.5, "risk": 0.30, "leverage": 1.0, "limit": 15},
            "Survive Sabotage":     {"time": 1.0, "risk": 0.50, "leverage": 0.8, "limit": 10},
            "Construct Defenses":   {"time": 5.0, "risk": 0.10, "leverage": 0.9, "limit": 10},
            "Scan Environment":     {"time": 1.5, "risk": 0.00, "leverage": 0.5, "limit": 30}
        }

    def calculate_ideal_points(self, time_cost, risk, leverage):
        risk_multiplier = 1.0 / max(0.1, (1.0 - risk))
        ideal = time_cost * self.BASE_RATE * risk_multiplier * leverage
        return max(1, int(round(ideal)))

    def evaluate_model(self):
        print(f"{'Action':<22} | {'Ideal Pts':<10} | {'Max Uses':<10} | {'Max Match Value':<15}")
        print("-" * 65)
        
        results = {}
        for action, stats in self.actions.items():
            pts = self.calculate_ideal_points(stats['time'], stats['risk'], stats['leverage'])
            max_val = pts * stats['limit']
            print(f"{action:<22} | +{pts:<9} | {stats['limit']:<10} | {max_val:<15}")
            results[action] = pts
            
        print("\n--- Playstyle Archetype Balance (Max Theoretical Points) ---")
        
        # Defender maxes out Repair, Defenses, Survive, Scan
        defender_pts = (results["Repair Node"] * 15) + (results["Construct Defenses"] * 10) + (results["Survive Sabotage"] * 10) + (results["Scan Environment"] * 10)
        
        # Killer maxes out Kills, Beacons, Scan
        killer_pts = (results["Kill Enemy"] * 4) + (results["Beacon Pressure"] * 20) + (results["Scan Environment"] * 15)
        
        # Runner gets the Objective, some Beacons, and Survival
        runner_pts = (results["Objective (Find)"] * 2) + (results["Objective (Carry)"] * 1) + (results["Objective (Slot/Win)"] * 1) + (results["Survive Sabotage"] * 5) + (results["Beacon Pressure"] * 5)
        
        print(f"Projected Match Score (Defender Archetype): ~{defender_pts} pts")
        print(f"Projected Match Score (Killer Archetype):   ~{killer_pts} pts")
        print(f"Projected Match Score (Runner Archetype):   ~{runner_pts} pts")
        
        print("\nConclusion: By capping the number of times objective steps can happen and adjusting Repair time, the point potential across all 3 playstyles normalizes to ~100-180 points!")

if __name__ == "__main__":
    model = PointEconomyModel()
    model.evaluate_model()
