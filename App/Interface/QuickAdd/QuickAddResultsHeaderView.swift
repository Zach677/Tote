import UIKit

final class QuickAddResultsHeaderView: UICollectionReusableView {
    private let titleLabel = UILabel()
    private let duplicateLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(totalCount: Int, duplicateCount: Int) {
        titleLabel.text = String(localized: "\(totalCount) Parcels Found")
        if duplicateCount > 0 {
            duplicateLabel.text = String(localized: "\(duplicateCount) already added")
            duplicateLabel.isHidden = false
        } else {
            duplicateLabel.text = nil
            duplicateLabel.isHidden = true
        }
    }
}

private extension QuickAddResultsHeaderView {
    func configureLayout() {
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        duplicateLabel.font = .preferredFont(forTextStyle: .footnote)
        duplicateLabel.adjustsFontForContentSizeCategory = true
        duplicateLabel.textColor = .secondaryLabel
        duplicateLabel.setContentHuggingPriority(.required, for: .horizontal)
        duplicateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stackView = UIStackView(arrangedSubviews: [titleLabel, duplicateLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .firstBaseline
        stackView.spacing = 8

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
    }
}
