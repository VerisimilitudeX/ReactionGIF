import SwiftUI

/// Horizontal chip selector for the reaction energy. Shared by the app and the
/// share extension.
struct VibePicker: View {
    @Binding var selection: Vibe

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Vibe.allCases) { option in
                    let isSelected = option == selection
                    Button {
                        Haptics.tap()
                        selection = option
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
