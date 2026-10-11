import Foundation

/// Journals are the durable outbox. A saved summary marks successful processing by the hosted API.
actor HostedWorkoutRelay {
    private let baseURL: URL
    private let network: URLSession

    init(baseURL: URL, network: URLSession = .shared) {
        self.baseURL = baseURL
        self.network = network
    }

    func sync(directory: URL) async throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasSuffix(".summary.json") {
            let receipt = file.deletingPathExtension().appendingPathExtension("summary.json")
            guard !FileManager.default.fileExists(atPath: receipt.path) else { continue }
            let data = try Data(contentsOf: file)
            guard let journal = try? Contracts.decoder.decode(WorkoutJournal.Document.self, from: data),
                  journal.state == .complete else { continue }
            var request = URLRequest(url: baseURL.appending(path: "api/workouts/summary"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            request.timeoutInterval = 15
            let (summary, response) = try await network.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: summary) as? [String: Any],
                  (body["workout_id"] as? String)?.lowercased() == journal.workoutId.lowercased() else {
                throw URLError(.badServerResponse)
            }
            try summary.write(to: receipt, options: .atomic)
        }
    }
}
