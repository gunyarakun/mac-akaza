import Foundation

struct ConvertCandidate: Decodable {
    let surface: String
    let yomi: String
    let cost: Float
}

typealias ConvertResult = [[ConvertCandidate]]

class JSONRPCClient {
    private let serverProcess: AkazaServerProcess
    private var nextID = 1
    private let requestQueue = DispatchQueue(label: "im.akaza.jsonrpc.request")
    private var readerQueue: DispatchQueue?

    private let lock = NSLock()
    private var pendingRequests: [Int: (Data?) -> Void] = [:]

    init(serverProcess: AkazaServerProcess) {
        self.serverProcess = serverProcess
        self.serverProcess.onRestart = { [weak self] in
            self?.startReaderLoop()
        }
    }

    func startReaderLoop() {
        guard let stdout = serverProcess.stdoutPipe else { return }

        let queue = DispatchQueue(label: "im.akaza.jsonrpc.reader")
        self.readerQueue = queue

        queue.async { [weak self] in
            let handle = stdout.fileHandleForReading
            var buffer = Data()

            while true {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    // EOF - server terminated
                    self?.failAllPending()
                    break
                }
                buffer.append(chunk)

                // Process complete lines
                while let newlineRange = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                    guard !lineData.isEmpty else { continue }
                    self?.handleResponse(lineData)
                }
            }
        }
    }

    func convertSync(yomi: String) -> ConvertResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?

        let requestID = requestQueue.sync { () -> Int in
            let id = self.nextID
            self.nextID += 1
            return id
        }

        lock.lock()
        pendingRequests[requestID] = { data in
            resultData = data
            semaphore.signal()
        }
        lock.unlock()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "convert",
            "params": ["yomi": yomi]
        ]

        requestQueue.async { [weak self] in
            guard let self = self,
                  let stdin = self.serverProcess.stdinPipe else {
                self?.completePending(id: requestID, data: nil)
                return
            }

            do {
                var data = try JSONSerialization.data(withJSONObject: request)
                data.append(0x0A) // newline
                stdin.fileHandleForWriting.write(data)
            } catch {
                NSLog("AkazaIME: failed to serialize JSON-RPC request: \(error)")
                self.completePending(id: requestID, data: nil)
            }
        }

        let timeout = semaphore.wait(timeout: .now() + 1.0)
        if timeout == .timedOut {
            NSLog("AkazaIME: JSON-RPC request timed out (id=\(requestID))")
            lock.lock()
            pendingRequests.removeValue(forKey: requestID)
            lock.unlock()
            return nil
        }

        guard let data = resultData else { return nil }

        do {
            let result = try JSONDecoder().decode(ConvertResult.self, from: data)
            return result
        } catch {
            NSLog("AkazaIME: failed to decode convert result: \(error)")
            return nil
        }
    }

    private func handleResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int else {
            return
        }

        if let result = json["result"] {
            if let resultData = try? JSONSerialization.data(withJSONObject: result) {
                completePending(id: id, data: resultData)
            } else {
                completePending(id: id, data: nil)
            }
        } else {
            if let error = json["error"] as? [String: Any] {
                NSLog("AkazaIME: JSON-RPC error (id=\(id)): \(error)")
            }
            completePending(id: id, data: nil)
        }
    }

    private func completePending(id: Int, data: Data?) {
        lock.lock()
        let callback = pendingRequests.removeValue(forKey: id)
        lock.unlock()
        callback?(data)
    }

    private func failAllPending() {
        lock.lock()
        let callbacks = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        for (_, callback) in callbacks {
            callback(nil)
        }
    }
}
