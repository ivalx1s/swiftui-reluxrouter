import Combine
import Relux
import SwiftUI

extension Relux.Navigation.ProjectingRouter {
	public enum ProjectedPage: Equatable {
		case known(Page)
		case external
	}
}

extension Relux.Navigation {
	
	/// A router class that manages navigation state and synchronizes between a `NavigationPath` and a projected path.
	///
	/// `ProjectingRouter` is designed to handle complex navigation scenarios, including programmatic navigation updates for other modules.
	///
	/// - Type Parameters:
	///   - Page: A type that conforms to both `PathComponent` and `Sendable`, representing the pages in the navigation stack.
	@MainActor
	@available(iOS 16, macOS 13, watchOS 9, tvOS 16, macCatalyst 16, *)
	public final class ProjectingRouter<Page>: Relux.Navigation.RouterProtocol, ObservableObject where Page: PathComponent, Page: Sendable {
		
		private var pipelines: Set<AnyCancellable> = []
		
		/// The current navigation path.
		///
		/// This property represents the actual navigation stack and is compatible with SwiftUI's navigation APIs.
		/// It is automatically updated when the projected path changes and vice versa.
		@Published public var path: NavigationPath = .init()
		
		/// A projection of the current path, including both known and external pages.
		///
		/// This property provides a more detailed view of the navigation stack, including pages that may have been
		/// added through external means (e.g., system back button). It is automatically synchronized with `path`.
		@Published public private(set) var pathProjection: [ProjectedPage] = []
		
		/// Initializes a new instance of `ProjectingRouter`.
		///
		/// This initializer sets up the necessary pipelines to keep `path` and `pathProjection` synchronized.
		public init() {
			initPipelines()
		}
		
		/// Resets the router to its initial state.
		///
		/// This method clears both the `path` and `pathProjection`, effectively resetting the navigation stack.
		public func restore() async {
			path = .init()
			pathProjection = []
		}
		
		/// Handles incoming Relux actions to modify the navigation state.
		///
		/// This method processes navigation actions and updates the router's state accordingly.
		/// It only responds to actions of type `Relux.Navigation.ProjectingRouter<Page>.Action`.
		///
		/// - Parameter action: The Relux action to be processed.
		public func reduce(with action: any Relux.Action) async {
			switch action as? Relux.Navigation.ProjectingRouter<Page>.Action {
				case .none: break
				case let .some(action):
					internalReduce(with: action)
			}
		}
	}
}

@available(iOS 16, macOS 13, watchOS 9, tvOS 16, macCatalyst 16, *)
extension Relux.Navigation.ProjectingRouter {
	
	@MainActor
	private func initPipelines() {
		setupPathToProjectionPipeline()
		setupProjectionToPathPipeline()
	}
	
	/// Sets up a Combine pipeline to synchronize the `path` with the `pathProjection`.
	///
	/// This pipeline observes changes in the `path` and updates the `pathProjection` accordingly:
	/// - If the path grows, it adds `.external` pages to the projection.
	/// - If the path shrinks, it removes pages from the end of the projection.
	///
	/// This ensures that the `pathProjection` always reflects the current state of the `path`,
	/// even when external navigation occurs (e.g., when a user taps the back button).
	private func setupPathToProjectionPipeline() {
		$path
			.receive(on: DispatchQueue.main)
			.sink { [weak self] path in
				guard let self else { return }
				let pagesDiff = path.count - self.pathProjection.count
				
				switch pagesDiff {
					case 0:
						// No change in path length, no action needed
						break
					case ..<0:
						// Path has shrunk, remove pages from the end of the projection
						self.pathProjection.removeLast(abs(pagesDiff))
					default:
						// Path has grown, add external pages to the projection
						let newExternalPages = Array<ProjectedPage>(repeating: .external, count: pagesDiff)
						self.pathProjection.append(contentsOf: newExternalPages)
				}
			}
			.store(in: &pipelines)
	}
	
	/// Sets up a Combine pipeline to synchronize the `pathProjection` with the `path`.
	///
	/// This pipeline observes changes in the `pathProjection` and updates the `path` accordingly:
	/// - If the projection grows, it adds known pages to the path (ignoring external pages).
	/// - If the projection shrinks, it removes pages from the end of the path.
	///
	/// This ensures that the `path` always reflects the current state of the `pathProjection`,
	/// allowing for programmatic navigation updates while maintaining synchronization with
	/// the actual navigation stack.
	private func setupProjectionToPathPipeline() {
		$pathProjection
			.receive(on: DispatchQueue.main)
			.sink { [weak self] projectedPath in
				guard let self else { return }
				let pagesDiff = projectedPath.count - self.path.count
				
				switch pagesDiff {
					case 0:
						// No change in projection length, no action needed
						break
					case ..<0:
						// Projection has shrunk, remove pages from the end of the path
						self.path.removeLast(abs(pagesDiff))
					default:
						// Projection has grown, add known pages to the path
						projectedPath
							.suffix(pagesDiff)
							.forEach { page in
								switch page {
									case .external:
										// Ignore external pages
										return
									case let .known(p):
										self.path.append(p)
								}
							}
				}
			}
			.store(in: &pipelines)
	}
}


@available(iOS 16, macOS 13, watchOS 9, tvOS 16, macCatalyst 16, *)
extension Relux.Navigation.ProjectingRouter {
	
	/// Internal method to handle navigation actions and update the router's state accordingly.
	/// This method is responsible for maintaining consistency between `pathProjection` and `path`.
	///
	/// - Parameter action: The navigation action to be processed.
	@MainActor
	func internalReduce(with action: Relux.Navigation.ProjectingRouter<Page>.Action) {
		switch action {
			case let .push(page, allowingDuplicates):
				// Handle pushing a new page onto the navigation stack
				switch allowingDuplicates {
					case true:
						// If duplicates are allowed, simply append the new page to the projection
						self.pathProjection.append(.known(page))
					case false:
						// If duplicates are not allowed, check if the page already exists in the projection
						// And act accordingly
						if self.pathProjection.contains(.known(page)) {
							return
						}
						self.pathProjection.append(.known(page))
				}

				self.path.append(page)
				
			case let .set(pages):
				// Handle setting an entirely new navigation stack
				// Convert the new pages to known projected pages
				self.pathProjection = pages.map { .known($0) }
				// Set the actual navigation path to the new pages
				self.path = .init(pages)
				
			case let .removeLast(count):
				// Handle removing pages from the end of the navigation stack
				// Calculate the actual number of items to remove, ensuring we don't remove more than exist
				let itemsCountToRemove = min(count, path.count)
				// Remove the calculated number of items from both the path and the projection
				self.path.removeLast(itemsCountToRemove)
				self.pathProjection.removeLast(itemsCountToRemove)
		}
	}
}