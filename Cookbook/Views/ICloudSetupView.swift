import SwiftUI

struct ICloudSetupView: View {
    @EnvironmentObject var store: RecipeStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "icloud.slash")
                .font(.system(size: 72))
                .foregroundColor(.gray)

            // Title
            Text("iCloud Not Available")
                .font(.title)
                .fontWeight(.bold)

            // Message
            Text("Cookbo requires iCloud Drive to sync your recipes across devices.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("To use Cookbo:")
                    .font(.headline)

                #if os(iOS)
                InstructionRow(number: 1, text: "Open the Settings app")
                InstructionRow(number: 2, text: "Sign in with your Apple ID")
                InstructionRow(number: 3, text: "Enable iCloud Drive")
                InstructionRow(number: 4, text: "Return to Cookbo")
                #else
                InstructionRow(number: 1, text: "Open System Settings")
                InstructionRow(number: 2, text: "Sign in with your Apple ID")
                InstructionRow(number: 3, text: "Enable iCloud Drive")
                InstructionRow(number: 4, text: "Return to Cookbo")
                #endif
            }
            .padding(24)
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #else
            .background(Color(uiColor: .secondarySystemBackground))
            #endif
            .cornerRadius(12)
            .padding(.horizontal, 32)

            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    store.checkICloudAvailability()
                }) {
                    Text("Check Again")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }

                Button(action: {
                    store.enableLocalStorage()
                }) {
                    Text("Continue with Local Storage")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Text("Local storage will keep your recipes on this device only. You can enable iCloud later in Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 4)

            Spacer()
        }
        .padding()
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    ICloudSetupView()
        .environmentObject(RecipeStore())
}
