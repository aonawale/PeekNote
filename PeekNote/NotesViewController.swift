//
//  MasterViewController.swift
//  PeekNote
//
//  Created by Ahmed Onawale on 3/20/16.
//  Copyright © 2016 Ahmed Onawale. All rights reserved.
//

import UIKit
import CoreData
import MGSwipeTableCell
import SWRevealViewController

private let cacheName = "NotesCache"

final class NotesViewController: UITableViewController, PreviewContext {
    
    typealias Cell = UITableViewCell
    typealias Element = NSManagedObject
    typealias ListView = UITableView
    
    var managedObjectContext: NSManagedObjectContext!
    var controllerState: ControllerState? {
        didSet {
            switch controllerState {
            case .Some(.Tag(let name)):
                title = name
            default:
                title = controllerState?.title()
            }
        }
    }
    var fetchPredicate: NSPredicate? {
        didSet {
            NSFetchedResultsController.deleteCacheWithName(cacheName)
        }
    }
    
    @IBOutlet weak var menuButton: UIBarButtonItem!
        
    // Mark: - Fetched Results Controller
    
    lazy var fetchedResultsController: NSFetchedResultsController = self.myFetchedResultsController()
    
    func myFetchedResultsController() -> NSFetchedResultsController {
        let fetchRequest = NSFetchRequest(entityName: Note.entityName())
        fetchRequest.predicate = self.fetchPredicate
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
            managedObjectContext: self.managedObjectContext,
            sectionNameKeyPath: nil,
            cacheName: cacheName)
        fetchedResultsController.delegate = self
        try! fetchedResultsController.performFetch()
        return fetchedResultsController
    }
    
    func configureTableView() {
        tableView.tableFooterView = UIView()
        tableView.estimatedRowHeight = tableView.rowHeight
        tableView.rowHeight = UITableViewAutomaticDimension
    }
    
    func configureSidebar() {
        guard let revealViewController = revealViewController() else { return }
        menuButton.target = revealViewController
        menuButton.action = #selector(SWRevealViewController.revealToggle(_:))
        view.addGestureRecognizer(revealViewController.panGestureRecognizer())
    }
    
    func configurePeepPop() {
        guard #available(iOS 9.0, *), traitCollection.forceTouchCapability == .Available else { return }
        registerForPreviewingWithDelegate(self, sourceView: view)
    }
    
    // MARK: - Life Cycle
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        configureSidebar()
        configurePeepPop()
        configureToolbar()
        splitViewController?.delegate = self
    }

    override func viewWillAppear(animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController!.collapsed
        super.viewWillAppear(animated)
    }
    
    func configureToolbar() {
        guard let state = controllerState else { return }
        switch state {
        case .Archive, .Reminders:
            navigationController?.toolbarHidden = true
        default:
            setToolbarItems(itemsForState(state), animated: false)
        }
    }
    
    func itemsForState(state: ControllerState) -> [UIBarButtonItem] {
        switch state {
        case .Trash:
            let item1 = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
            let item2 = UIBarButtonItem(title: "Empty Trash", style: .Plain, target: self, action: #selector(emptyTrash(_:)))
            item2.enabled = fetchedResultsController.fetchedObjects?.count > 0
            let item3 = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
            return [item1, item2, item3]
        default:
            let count = fetchedResultsController.fetchedObjects?.count ?? 0
            let title = count < 1 ? "No Notes" : count > 1 ? "\(count) Notes" : "\(count) Note"
            let item1 = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
            let item2 = UIBarButtonItem(title: title, style: .Plain, target: nil, action: nil)
            item2.tintColor = .blackColor()
            let item3 = UIBarButtonItem(barButtonSystemItem: .FlexibleSpace, target: nil, action: nil)
            let item4 = UIBarButtonItem(barButtonSystemItem: .Compose, target: self, action: #selector(newNote(_:)))
            return [item1, item2, item3, item4]
        }
    }
    
    func emptyTrash(sender: UIBarButtonItem) {
        let title = "Empty Trash"
        let message = "All notes in Trash will be permanently deleted"
        Alert.warn(self, title: title, message: message, confirmTitle: "Empty Trash", confirmAction: { [weak self] _ in
            let predicate = NSPredicate(format: "state == \(State.Trashed.rawValue)")
            self?.managedObjectContext.deleteAllEntity(Note.self, matchingPredicate: predicate)
            if #available(iOS 9, *) {
                // refetch objects from persistent store if the deletions was performed
                // directly on the NSPersistenceStore by NSBatchDeleteRequest
                NSFetchedResultsController.deleteCacheWithName(cacheName)
                self?.performFetch()
                self?.tableView.reloadSection(0)
            } else {
                self?.managedObjectContext.saveChanges()
            }
            sender.enabled = false
        }, cancelAction: nil)
    }
    
    func newNote(sender: UIBarButtonItem?) {
        guard let state = controllerState else { return }
        let note = Note(title: "", body: "", insertIntoManagedObjectContext: managedObjectContext)
        switch state {
        case .Tag(let name):
            let predicate = NSPredicate(format: "name == %@", name!)
            guard let tag = managedObjectContext.fetchEntity(Tag.self, matchingPredicate: predicate)?.first as? Tag else {
                controllerState = ControllerState.Notes(nil)
                fetchedResultsController.fetchRequest.predicate = NSPredicate(format: "state == \(State.Normal.rawValue)")
                performFetch()
                tableView.reloadSection(0)
                break
            }
            tag.notes.insert(note)
        default: break
        }
        performSegueWithIdentifier("showDetail", sender: note)
    }

    // MARK: - Segues

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
        guard let identifier = segue.identifier else { return }
        switch identifier {
        case "showDetail":
            let controller = segue.destinationViewController.contentViewController as! NoteDetailViewController
            controller.managedObjectContext = managedObjectContext
            controller.note = sender as! Note
        default:
            break
        }
    }
}

@available(iOS 9.0, *)
extension NotesViewController: UIViewControllerPreviewingDelegate {
    // MARK: UIViewControllerPreviewingDelegate
    
    /// Create a previewing view controller to be shown at "Peek".
    func previewingContext(previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        // Obtain the index path and the cell that was pressed.
        guard let indexPath = tableView.indexPathForRowAtPoint(location),
        cell = tableView.cellForRowAtIndexPath(indexPath),
        detailViewController = storyboard?.instantiateViewControllerWithIdentifier("NoteDetailViewController") as? NoteDetailViewController,
        note = fetchedResultsController.objectAtIndexPath(indexPath) as? Note else { return nil }
        detailViewController.note = note
        detailViewController.managedObjectContext = managedObjectContext
        detailViewController.delegate = self
        
        /*
         Set the height of the preview by setting the preferred content size of the detail view controller.
         Width should be zero, because it's not used in portrait.
         */
//        let minimumSize = detailViewController.view.systemLayoutSizeFittingSize(UILayoutFittingCompressedSize)
//        detailViewController.preferredContentSize = CGSize(width: 0.0, height: minimumSize.height)
        
        // Set the source rect to the cell frame, so surrounding elements are blurred.
        previewingContext.sourceRect = cell.frame
        
        return detailViewController
    }
    
    /// Present the view controller for the "Pop" action.
    func previewingContext(previewingContext: UIViewControllerPreviewing, commitViewController viewControllerToCommit: UIViewController) {
        // Reuse the "Peek" view controller for presentation.
        showViewController(viewControllerToCommit, sender: self)
    }
    
}

extension NotesViewController: UISplitViewControllerDelegate {
    
    // MARK: - Split view
    
    func splitViewController(splitViewController: UISplitViewController, collapseSecondaryViewController secondaryViewController:UIViewController, ontoPrimaryViewController primaryViewController:UIViewController) -> Bool {
        guard let secondaryAsNavController = secondaryViewController as? UINavigationController,
            viewController = secondaryAsNavController.topViewController as? NoteDetailViewController else { return false }
        // Return true to indicate that we have handled the collapse by doing nothing;
        //the secondary controller will be discarded.
        return viewController.note == nil
    }
    
}

extension NotesViewController: MGSwipeTableCellDelegate {
    
    // Mark: MGSwipeTableCellDelegate
    
    func swipeTableCell(cell: MGSwipeTableCell!, swipeButtonsForDirection direction: MGSwipeDirection, swipeSettings: MGSwipeSettings!, expansionSettings: MGSwipeExpansionSettings!) -> [AnyObject]! {
        guard let state = controllerState where direction == .RightToLeft else { return nil }
        swipeSettings.transition = .Border
        expansionSettings.buttonIndex = 0
        expansionSettings.fillOnTrigger = true
        expansionSettings.threshold = 1
        
        func setupButton(button: UIButton...) {
            button.forEach {
                let spacing: CGFloat = 5.0
                let imageSize = $0.imageView!.image!.size
                $0.titleEdgeInsets = UIEdgeInsets(top: 0.0, left: -imageSize.width, bottom: -(imageSize.height + spacing), right: 0.0)
                let labelString = NSString(string: $0.titleLabel!.text!)
                let titleSize = labelString.sizeWithAttributes([NSFontAttributeName: $0.titleLabel!.font])
                $0.imageEdgeInsets = UIEdgeInsets(top: -(titleSize.height + spacing), left: 0.0, bottom: 0.0, right: -titleSize.width)
            }
        }

        let trash = MGSwipeButton(title: "Trash", icon: UIImage(named: "Trash Filled"), backgroundColor: .deleteColor(), padding: 5)
        let archive = MGSwipeButton(title: "Archive", icon: UIImage(named: "Archive Filled"), backgroundColor: .trashColor(), padding: 5)
        let unarchive = MGSwipeButton(title: "Unarchive", icon: UIImage(named: "Delete Archive"), backgroundColor: .trashColor(), padding: 5)
        let recover = MGSwipeButton(title: "Recover", icon: UIImage(named: "Recover Trash"), backgroundColor: .trashColor(), padding: 5)
        let delete = MGSwipeButton(title: "Delete", icon: UIImage(named: "Delete Filled"), backgroundColor: .deleteColor(), padding: 5)
        
        setupButton(trash, archive, unarchive, recover, delete)
        
        switch state {
        case .Archive:
            return [trash, unarchive]
        case .Trash:
            return [delete, recover]
        default:
            return [trash, archive]
        }
    }
    
    func swipeTableCell(cell: MGSwipeTableCell!, tappedButtonAtIndex index: Int, direction: MGSwipeDirection, fromExpansion: Bool) -> Bool {
        guard let indexPath = tableView.indexPathForCell(cell),
        note = fetchedResultsController.objectAtIndexPath(indexPath) as? Note else { return false }
        switch note.state {
        case .Normal where index == 1:
            note.state = .Archived
        case .Normal where index == 0:
            note.state = .Trashed
        case .Archived where index == 1:
            note.state = .Normal
        case .Archived where index == 0:
            note.state = .Trashed
        case .Trashed where index == 1:
            note.state = .Normal
        case .Trashed where index == 0:
            let message = "Are you sure you want to delete this note"
            Alert.warn(self, title: nil, message: message, confirmTitle: "Delete", confirmAction: { [weak self] _ in
                self?.managedObjectContext.deleteObject(note)
                self?.managedObjectContext.saveChanges()
            }, cancelAction: { _ in
                cell.hideSwipeAnimated(true)
            })
        default:
            break
        }
        note.updatedDate = NSDate()
        managedObjectContext.saveChanges()
        return false
    }
}

extension NotesViewController: FetchedTableList {
    
    // MARK: Fetched Controller
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        tableWillChangeContent()
    }
    
    func controller(controller: NSFetchedResultsController,
                          didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int,
                                           forChangeType type: NSFetchedResultsChangeType) {
        tableDidChangeSection(sectionIndex, withChangeType: type)
    }
    
    func controller(controller: NSFetchedResultsController,
                          didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?,
                                          forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        tableDidChangeObjectAtIndexPath(indexPath, withChangeType: type, newIndexPath: newIndexPath)
        if type == .Delete || type == .Insert {
            configureToolbar()
        }
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        tableDidChangeContent()
    }
    
    func listView(listView: ListView, configureCell cell: Cell, withElement element: Element, atIndexPath indexPath: NSIndexPath) {
        guard let cell = cell as? NoteTableViewCell,
            note = element as? Note else { return }
        cell.note = note
        cell.delegate = self
    }
    
    // MARK: Table View
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return numberOfRowsInSection(section)
    }
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return numberOfSections
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableCellAtIndexPath(indexPath) as! NoteTableViewCell
        return cell
    }
    
    func cellIdentifierForIndexPath(indexPath: NSIndexPath) -> String {
        return "Note Cell"
    }
    
    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch controllerState {
        case .Some(.Trash):
            let view = PatternView(frame: CGRect(origin: CGPoint(x: 8, y: 0), size: CGSize(width: tableView.frame.width, height: 44.0)))
            let label = UILabel(frame: view.frame)
            label.numberOfLines = 0
            label.lineBreakMode = .ByTruncatingHead
            label.text = "Notes older than 7 days in Trash will be permanently deleted."
            label.font = .italicSystemFontOfSize(17)
            label.textColor = .subTextColor()
            view.addSubview(label)
            return view
        default:
            return nil
        }
    }
    
    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch controllerState {
        case .Some(.Trash):
            return 44.0
        default:
            return 0.0
        }
    }
    
}

extension NotesViewController {
    
    // MARK: - UITableViewDelegate
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let note = fetchedResultsController.objectAtIndexPath(indexPath)
        performSegueWithIdentifier("showDetail", sender: note)
    }
    
}
