import SwiftUI
import UIKit

/// Device code authorization sheet allowing users to connect Real-Debrid without sharing passwords
@MainActor
public struct DeviceAuthorizationView: View {
    public let debridClient: RealDebridClientProtocol
    public let onAuthorized: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var deviceCodeResponse: RDDeviceCodeResponse?
    @State private var isRequestingCode = true
    @State private var remainingSeconds: Int = 600
    @State private var errorMessage: String?
    @State private var codeCopied = false
    @State private var flowTask: Task<Void, Never>?
    
    public init(
        debridClient: RealDebridClientProtocol = RealDebridClient.shared,
        onAuthorized: @escaping () -> Void
    ) {
        self.debridClient = debridClient
        self.onAuthorized = onAuthorized
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 24) {
                
                // Real-Debrid Header
                VStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text("Connect Real-Debrid")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Authorize this iPhone without sharing your Real-Debrid password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 16)
                
                if isRequestingCode {
                    Spacer()
                    ProgressView("Generating activation code...")
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    ErrorStateBanner(message: error) {
                        startAuthorizationFlow()
                    }
                    Spacer()
                } else if let code = deviceCodeResponse {
                    // Verification Code Box
                    VStack(spacing: 14) {
                        Text("ENTER THIS CODE AT REAL-DEBRID:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Text(code.userCode)
                            .font(.system(size: 38, weight: .heavy, design: .monospaced))
                            .tracking(4)
                            .foregroundColor(.primary)
                            .padding(.vertical, 8)
                        
                        VStack(spacing: 12) {
                            Button(action: copyCode) {
                                Label(codeCopied ? "Copied!" : "Copy Code", systemImage: codeCopied ? "checkmark" : "doc.on.doc")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                            
                            Button(action: openVerificationURL) {
                                Label("Open Website", systemImage: "arrow.up.right.square")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .liquidGlass(style: .card, cornerRadius: 22)
                    .padding(.horizontal, 20)
                    
                    // Polling Status Indicator
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Waiting for authorization on real-debrid.com/device...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Code expires in \(remainingSeconds / 60):\(String(format: "%02d", remainingSeconds % 60))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    Spacer()
                }
            }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelFlow()
                        dismiss()
                    }
                }
            }
            .onAppear {
                startAuthorizationFlow()
            }
            .onDisappear {
                cancelFlow()
            }
        }
    }
    
    // MARK: - Authorization Flow Execution
    
    private func startAuthorizationFlow() {
        cancelFlow()
        isRequestingCode = true
        deviceCodeResponse = nil
        errorMessage = nil
        codeCopied = false
        flowTask = Task {
            do {
                let response = try await debridClient.requestDeviceCode()
                try Task.checkCancellation()
                deviceCodeResponse = response
                remainingSeconds = max(0, response.expiresIn)
                isRequestingCode = false
                let deadline = Date().addingTimeInterval(Double(max(0, response.expiresIn)))
                let interval = Double(max(1, response.interval))
                var nextPoll = Date().addingTimeInterval(interval)
                while Date() < deadline {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    try Task.checkCancellation()
                    remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                    guard Date() < deadline else { break }
                    if Date() >= nextPoll {
                        nextPoll = Date().addingTimeInterval(interval)
                        do {
                            let credentials = try await debridClient.pollForCredentials(deviceCode: response.deviceCode)
                            try Task.checkCancellation()
                            _ = try await debridClient.exchangeCodeForToken(clientId: credentials.clientId,
                                      clientSecret: credentials.clientSecret, deviceCode: response.deviceCode)
                            try Task.checkCancellation()
                            onAuthorized()
                            dismiss()
                            return
                        } catch RealDebridError.deviceAuthPending { continue }
                    }
                }
                throw RealDebridError.deviceAuthExpired
            } catch {
                guard !Task.isCancelled else { return }
                isRequestingCode = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copyCode() {
        #if os(iOS)
        if let code = deviceCodeResponse?.userCode {
            UIPasteboard.general.string = code
            codeCopied = true
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                codeCopied = false
            }
        }
        #endif
    }
    
    private func openVerificationURL() {
        #if os(iOS)
        if let url = URL(string: "https://real-debrid.com/device") {
            UIApplication.shared.open(url)
        }
        #endif
    }
    
    private func cancelFlow() {
        flowTask?.cancel()
        flowTask = nil
    }
}
