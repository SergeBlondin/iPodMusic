// CoverFlowLayout.swift
import UIKit

class CoverFlowLayout: UICollectionViewLayout {
    
    // MARK: - Configuration
    
    var itemWidth: CGFloat = 200
    var itemHeight: CGFloat = 300
    var scaleFactor: CGFloat = 0.7
    var alphaFactor: CGFloat = 0.3
    var rotationAngle: CGFloat = .pi / 6 // 30 degrees - more subtle
    var spacing: CGFloat = 20
    
    private var cache: [UICollectionViewLayoutAttributes] = []
    
    override func prepare() {
        cache.removeAll(keepingCapacity: true)
        
        guard let collectionView = collectionView else { return }
        
        let itemSize = CGSize(width: itemWidth, height: itemHeight)
        let itemsCount = collectionView.numberOfItems(inSection: 0)
        
        guard itemsCount > 0 else { return }
        
        // Center the collection view content
        let collectionViewWidth = collectionView.bounds.width
        let totalWidth = (CGFloat(itemsCount) * itemWidth) + (CGFloat(itemsCount - 1) * spacing)
        let contentOffsetX = max(0, (collectionViewWidth - totalWidth) / 2)
        
        // Calculate center index for perspective effects
        let itemCenterIndex = CGFloat(itemsCount - 1) / 2
        
        for index in 0..<itemsCount {
            let indexPath = IndexPath(item: index, section: 0)
            
            // Calculate position relative to center
            let offsetFromCenter = CGFloat(index) - itemCenterIndex
            let distanceFromCenter = abs(offsetFromCenter)
            
            // Calculate scale and alpha based on distance from center
            let scale = 1.0 - (distanceFromCenter * 0.15)
            let alpha = 1.0 - (distanceFromCenter * 0.25)
            
            // Calculate rotation angle (positive for right, negative for left)
            let angle = offsetFromCenter * rotationAngle
            
            // Calculate x position - center the entire collection
            let x = contentOffsetX + (CGFloat(index) * (itemWidth + spacing))
            let y = (collectionView.bounds.height - itemHeight) / 2
            
            // Create 3D perspective transform
            var perspectiveTransform = CATransform3D()
            perspectiveTransform.m34 = -1 / 500 // Perspective intensity
            perspectiveTransform = CATransform3D(rotationAngle: angle, axis: (0, 1, 0))
            perspectiveTransform = CATransform3D(scale: scale, scale: scale, scale: 1)
            
            let attributes = UICollectionViewLayoutAttributes(withIndexPath: indexPath)
            attributes.frame = CGRect(x: x, y: y, width: itemWidth, height: itemHeight)
            attributes.transform3D = perspectiveTransform
            attributes.alpha = max(alpha, 0.3)
            attributes.zIndex = Int(itemsCount - distanceFromCenter)
            
            cache.append(attributes)
        }
    }
    
    override func layoutAttributesForItems(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return cache.filter { attributes in
            rect.intersects(attributes.frame)
        }
    }
    
    override var collectionViewContentSize: CGSize {
        guard let collectionView = collectionView else {
            return CGSize.zero
        }
        
        let itemCount = collectionView.numberOfItems(inSection: 0)
        let totalWidth = (CGFloat(itemCount) * itemWidth) + (CGFloat(itemCount - 1) * spacing)
        // Add extra width to ensure last item is fully visible when scrolled to
        let extraPadding = collectionView.bounds.width - itemWidth
        return CGSize(width: totalWidth + extraPadding, height: collectionView.bounds.height)
    }
    
    override func invalidatesContentOffset() -> Bool {
        return true
    }
}

// MARK: - CoverFlowCell

class CoverFlowCell: UICollectionViewCell {
    
    let albumImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.borderWidth = 2
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.layer.shadowOpacity = 0.5
        imageView.layer.shadowRadius = 10
        imageView.layer.shadowColor = UIColor.black.cgColor
        return imageView
    }()
    
    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 16)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.addSubview(albumImageView)
        contentView.addSubview(titleLabel)
        
        albumImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            albumImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            albumImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            albumImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            albumImageView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -10),
            
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        albumImageView.image = nil
        titleLabel.text = nil
    }
    
    func configure(with album: Album) {
        albumImageView.image = album.artwork
        titleLabel.text = album.title
    }
}

// MARK: - Album model

struct Album {
    let id: UUID
    let title: String
    let artwork: UIImage
}

// MARK: - CoverFlowViewController

class CoverFlowViewController: UIViewController {
    
    private var collectionView: UICollectionView!
    private var albums: [Album] = []
    private var currentCenterIndex: Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        loadAlbums()
    }
    
    private func setupCollectionView() {
        let layout = CoverFlowLayout()
        layout.itemWidth = 200
        layout.itemHeight = 300
        layout.spacing = 25
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .black
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.register(CoverFlowCell.self, forCellWithReuseIdentifier: "CoverFlowCell")
        collectionView.dataSource = self
        collectionView.delegate = self
        
        view.addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 400)
        ])
    }
    
    private func loadAlbums() {
        albums = [
            Album(id: UUID(), title: "Album One", artwork: UIImage(systemName: "music.square")!),
            Album(id: UUID(), title: "Album Two", artwork: UIImage(systemName: "music.square")!),
            Album(id: UUID(), title: "Album Three", artwork: UIImage(systemName: "music.square")!),
            Album(id: UUID(), title: "Album Four", artwork: UIImage(systemName: "music.square")!),
            Album(id: UUID(), title: "Album Five", artwork: UIImage(systemName: "music.square")!)
        ]
        
        collectionView.reloadData()
        centerCurrentAlbum(animated: false)
    }
    
    // Center the selected album when scrolling ends
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Don't center here - layout may not be complete
    }
    
    private func centerCurrentAlbum(animated: Bool = true) {
        guard !albums.isEmpty else { return }
        
        let visibleCenterX = collectionView.bounds.midX + collectionView.contentOffset.x
        
        // Find closest item to center using layout attributes
        var closestIndex: Int = 0
        var minDistance = CGFloat.greatestFiniteNumber
        
        let visibleAttributes = collectionView.layoutAttributesForItems(in: collectionView.bounds)
        
        for attr in visibleAttributes {
            let distance = abs((attr.frame.midX) - visibleCenterX)
            if distance < minDistance {
                minDistance = distance
                closestIndex = attr.indexPath.item
            }
        }
        
        // Only update if changed
        if closestIndex != currentCenterIndex {
            currentCenterIndex = closestIndex
            
            let attr = collectionView.layoutAttributesForItem(at: IndexPath(item: closestIndex, section: 0))
            guard let attributes = attr else { return }
            
            let offsetX = attributes.frame.midX - collectionView.bounds.midX
            collectionView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: animated)
        }
    }
    
    // Scroll to center item programmatically
    func scrollToAlbum(at index: Int, animated: Bool = true) {
        guard index >= 0 && index < albums.count else { return }
        
        let attr = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        guard let attributes = attr else { return }
        
        let offsetX = attributes.frame.midX - collectionView.bounds.midX
        collectionView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: animated)
        currentCenterIndex = index
    }
}

extension CoverFlowViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return albums.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CoverFlowCell", for: indexPath) as! CoverFlowCell
        cell.configure(with: albums[indexPath.item])
        return cell
    }
}

extension CoverFlowViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let selectedAlbum = albums[indexPath.item]
        print("Selected: \(selectedAlbum.title)")
        
        // Center the selected item
        scrollToAlbum(at: indexPath.item, animated: true)
        
        // Add your navigation logic here, e.g., push to album detail view
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        centerCurrentAlbum(animated: true)
    }
    
    // Optional: provide visual feedback during scrolling
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Could add additional effects here based on scroll position
    }
}