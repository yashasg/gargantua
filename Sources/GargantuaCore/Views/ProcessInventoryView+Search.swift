import SwiftUI

// Search field for the Process Inventory pane. Unlike filtering the captured
// snapshot, typing here drives a full-table find pass (see
// `ProcessInventorySession.search`), so processes outside the top-N — idle
// daemons, low-resource helpers — are still findable.
extension ProcessInventoryView {
    var searchBar: some View {
        HStack(spacing: GargantuaSpacing.space1) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GargantuaColors.ink4)

            ZStack(alignment: .leading) {
                if searchQuery.isEmpty {
                    Text("Search all processes by name, path, PID, or parent")
                        .font(GargantuaFonts.body)
                        .foregroundStyle(GargantuaColors.ink3)
                        .allowsHitTesting(false)
                }

                TextField("", text: $searchQuery)
                    .font(GargantuaFonts.body)
                    .foregroundStyle(GargantuaColors.ink)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search processes")
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)

            if session.isSearching {
                AccretionDiskView(activityRate: 18, size: 12, color: GargantuaColors.accretion)
                    .frame(width: 16, height: 16)
            } else if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GargantuaColors.ink4)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, GargantuaSpacing.space2)
        .padding(.vertical, GargantuaSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: GargantuaRadius.small)
                .fill(isSearchFocused ? GargantuaColors.surface4 : GargantuaColors.surface3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GargantuaRadius.small)
                .stroke(isSearchFocused ? GargantuaColors.borderFocus : GargantuaColors.borderEm, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = true }
        .padding(.horizontal, GargantuaSpacing.space4)
        .padding(.top, GargantuaSpacing.space3)
        .padding(.bottom, GargantuaSpacing.space1)
    }
}
