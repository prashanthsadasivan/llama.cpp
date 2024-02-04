import SwiftUI
import Foundation
import Combine

struct DownloadButton: View {
    class DownloadState : ObservableObject {
        @Published var status: String = ""
        @Published  var progress = 0.0
        @Published var model: Model?
        var downloadTask: URLSessionDownloadTask?
        var progressObserver: AnyCancellable?

        static func withStatus(_ status: String) -> DownloadState {
            return DownloadState(status: status)
        }

        init(status: String, downloadTask: URLSessionDownloadTask? = nil, progress: Double = 0.0, model: Model? = nil, progressObserver: AnyCancellable? = nil) {
            self.status = status
            self.downloadTask = downloadTask
            self.progress = progress
            self.model = model
            self.progressObserver = progressObserver
        }

        static func getFileURL(filename: String) -> URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        }

        func download(modelName: String, modelUrl: String, filename: String) {
            status = "downloading"
            print("Downloading model \(modelName) from \(modelUrl)")
            guard let url = URL(string: modelUrl) else { return }
            let fileURL = DownloadState.getFileURL(filename: filename)

            downloadTask = URLSession.shared.downloadTask(with: url) { temporaryURL, response, error in
                if  let error = error {
                    print("Error: \(error.localizedDescription)")
                    return
                }

                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                    print("Server error!")
                    return
                }

                do {
                    if let temporaryURL = temporaryURL {
                        try FileManager.default.copyItem(at: temporaryURL, to: fileURL)
                        print("Writing to \(filename) completed")
                        DispatchQueue.main.async {
                            self.model =  Model(name: modelName, url: modelUrl, filename: filename, status: "downloaded")
                            self.status = "downloaded"
                        }
                    }
                } catch  {
                    // Handle the error locally, for example, by logging it or updating the state
                    print("Error occurred: \(error)")
                    // Optionally, update some state or perform other non-throwing actions
                }
            }

            self.progressObserver = downloadTask?.progress
                .publisher(for: \.fractionCompleted).receive(on: DispatchQueue.main)
                .sink { [weak self] fractionCompleted in
                    self?.progress = fractionCompleted
                }

            downloadTask?.resume()
        }
    }

    @StateObject var downloadState: DownloadState
    @ObservedObject private var llamaState: LlamaState
    private var modelName: String
    private var modelUrl: String
    private var filename: String

    private func checkFileExistenceAndUpdateStatus() {
    }

    init(llamaState: LlamaState, modelName: String, modelUrl: String, filename: String) {
        self.llamaState = llamaState
        self.modelName = modelName
        self.modelUrl = modelUrl
        self.filename = filename
        let fileURL = DownloadState.getFileURL(filename: filename)
        _downloadState = StateObject(wrappedValue: DownloadState.withStatus(FileManager.default.fileExists(atPath: fileURL.path) ? "downloaded" : "download"
))
    }

    var body: some View {
        VStack {
            if downloadState.status == "download" {
                Button(action: {
                    downloadState.download(modelName: modelName, modelUrl: modelUrl, filename: filename)
                }) {
                    Text("Download " + modelName)
                }
            } else if downloadState.status == "downloading" {
                Button(action: {
                    downloadState.downloadTask?.cancel()
                    downloadState.status = "download"
                }) {
                    Text("\(modelName) (Downloading \(Int(downloadState.progress * 100))%)")
                }
            } else if downloadState.status == "downloaded" {
                Button(action: {
                    let fileURL = DownloadState.getFileURL(filename: filename)
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        downloadState.download(modelName: modelName, modelUrl: modelUrl, filename: filename)
                        return
                    }
                    do {
                        try llamaState.loadModel(modelUrl: fileURL)
                    } catch let err {
                        print("Error: \(err.localizedDescription)")
                    }
                }) {
                    Text("Load \(modelName)")
                }
            } else {
                Text("Unknown status: \(downloadState.status)")
            }
        }
        .onDisappear() {
            downloadState.downloadTask?.cancel()
        }
        .onChange(of: llamaState.cacheCleared) { newValue in
            if newValue {
                downloadState.downloadTask?.cancel()
                let fileURL = DownloadState.getFileURL(filename: filename)
                downloadState.status = FileManager.default.fileExists(atPath: fileURL.path) ? "downloaded" : "download"
            }
        }
    }
}

// #Preview {
//    DownloadButton(
//        llamaState: LlamaState(),
//        modelName: "TheBloke / TinyLlama-1.1B-1T-OpenOrca-GGUF (Q4_0)",
//        modelUrl: "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_0.gguf?download=true",
//        filename: "tinyllama-1.1b-1t-openorca.Q4_0.gguf"
//    )
// }
