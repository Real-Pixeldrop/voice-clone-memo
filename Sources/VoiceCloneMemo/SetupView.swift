import SwiftUI

struct SetupView: View {
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "mic.badge.plus")
                    .font(.title2)
                Text("Voice Clone Memo")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()

            Divider()

            if setupManager.isSettingUp {
                // Installation in progress
                installingView
            } else if let error = setupManager.error {
                // Error view
                errorView(error)
            } else {
                // Welcome / first launch
                welcomeView
            }
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Welcome

    var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("Bienvenue !")
                .font(.title)
                .fontWeight(.bold)

            Text("Voice Clone Memo utilise Qwen3-TTS pour cloner ta voix et générer des mémos vocaux. 100% local, gratuit, privé.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "desktopcomputer", text: "Tourne sur ton Mac, rien dans le cloud")
                featureRow(icon: "lock.shield", text: "Ta voix reste sur ton ordinateur")
                featureRow(icon: "infinity", text: "Gratuit et illimité, pour toujours")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                Button(action: { setupManager.startSetup() }) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Installer Qwen3-TTS")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { setupManager.skipSetup() }) {
                    Text("Passer (utiliser un provider cloud)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("Tout s'installe automatiquement. Le modèle (~2-4 Go) se télécharge au premier lancement.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Installing

    var installingView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Animated icon
            ProgressView()
                .scaleEffect(1.5)

            Text("Installation en cours...")
                .font(.title2)
                .fontWeight(.semibold)

            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: setupManager.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 8)

                Text(setupManager.currentStep)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(Int(setupManager.progress * 100))%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 4) {
                Text("Ne ferme pas l'application")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("Le téléchargement peut prendre 10-15 minutes selon ta connexion.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Error

    func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Erreur d'installation")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button(action: { setupManager.startSetup() }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Réessayer")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { setupManager.skipSetup() }) {
                    Text("Passer (utiliser un provider cloud)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Helpers

    func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.callout)
        }
    }
}
