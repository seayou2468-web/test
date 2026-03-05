#import "AFCViewController.h"
#import "AFCEditorViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AFCViewController () {
    UITableView *_tableView;
    NSArray *_items;
}

- (void)renameItem:(NSDictionary *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename" message:item[@"name"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = item[@"name"]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = alert.textFields[0].text;
        if (newName.length > 0 && ![newName isEqualToString:item[@"name"]]) {
            NSString *oldPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:item[@"name"]];
            NSString *newPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:newName];
            [self.connectionManager afcRenamePath:oldPath toPath:newPath completion:^(NSError *error) {
                if (!error) [self loadData];
            }];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = _items[indexPath.row];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSString *fullPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:item[@"name"]];
        [self.connectionManager afcDeleteFile:fullPath completion:^(NSError *error) {
            completionHandler(error == nil);
            if (!error) [self loadData];
        }];
    }];

    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self renameItem:item];
        completionHandler(YES);
    }];
    renameAction.backgroundColor = [UIColor systemOrangeColor];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction]];
}
@end

@implementation AFCViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.currentPath ?: (self.bundleIdForHouseArrest ?: @"/");
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTapped)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)]
    ];

    [self loadData];
}

- (void)loadData {
    NSString *path = self.currentPath ?: @"/";
    void (^completion)(NSArray *, NSError *) = ^(NSArray *items, NSError *error) {
        if (error) {
            NSLog(@"AFC Error: %@", error);
        } else {
            self->_items = [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                if ([a[@"isDirectory"] boolValue] != [b[@"isDirectory"] boolValue]) {
                    return [a[@"isDirectory"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
                }
                return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
            }];
            dispatch_async(dispatch_get_main_queue(), ^{ [self->_tableView reloadData]; });
        }
    };

    if (self.bundleIdForHouseArrest) {
        [self.connectionManager houseArrestListDirectory:path bundleId:self.bundleIdForHouseArrest isDocuments:self.isDocumentsForHouseArrest completion:completion];
    } else {
        [self.connectionManager afcListDirectory:path completion:completion];
    }
}

- (void)addTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Item" message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"New Folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self createNewFolder];
    }]];
[alert addAction:[UIAlertAction actionWithTitle:@"New Text File" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self createNewFile];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Upload File" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createNewFile {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New File" message:@"Enter filename" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"filename.txt"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields[0].text;
        if (name.length > 0) {
            NSString *fullPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:name];
            [self.connectionManager afcWriteFile:fullPath data:[NSData data] completion:^(NSError *error) {
                if (!error) [self loadData];
            }];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
        NSString *fullPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:url.lastPathComponent];
        [self.connectionManager afcWriteFile:fullPath data:data completion:^(NSError *error) {
            if (!error) [self loadData];
        }];
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
    NSDictionary *item = _items[indexPath.row];
    cell.textLabel.text = item[@"name"];
    BOOL isDir = [item[@"isDirectory"] boolValue];
    cell.imageView.image = [UIImage systemImageNamed:isDir ? @"folder.fill" : @"doc.fill"];
    cell.imageView.tintColor = isDir ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    if (!isDir) cell.detailTextLabel.text = [NSString stringWithFormat:@"%lld bytes", [item[@"size"] longLongValue]];
    else cell.detailTextLabel.text = nil;
    cell.accessoryType = isDir ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = _items[indexPath.row];
    NSString *fullPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:item[@"name"]];

    if ([item[@"isDirectory"] boolValue]) {
        AFCViewController *next = [[AFCViewController alloc] init];
        next.connectionManager = self.connectionManager;
        next.currentPath = fullPath;
        next.bundleIdForHouseArrest = self.bundleIdForHouseArrest;
        next.isDocumentsForHouseArrest = self.isDocumentsForHouseArrest;
        [self.navigationController pushViewController:next animated:YES];
    } else {
        AFCEditorViewController *editor = [[AFCEditorViewController alloc] init];
        editor.connectionManager = self.connectionManager;
        editor.filePath = fullPath;
        [self.navigationController pushViewController:editor animated:YES];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *item = _items[indexPath.row];
        NSString *fullPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:item[@"name"]];
        [self.connectionManager afcDeleteFile:fullPath completion:^(NSError *error) {
            if (!error) [self loadData];
        }];
    }
}


- (void)renameItem:(NSDictionary *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename" message:item[@"name"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = item[@"name"]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newName = alert.textFields[0].text;
        if (newName.length > 0 && ![newName isEqualToString:item[@"name"]]) {
            NSString *oldPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:item[@"name"]];
            NSString *newPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:newName];
            [self.connectionManager afcRenamePath:oldPath toPath:newPath completion:^(NSError *error) {
                if (!error) [self loadData];
            }];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = _items[indexPath.row];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        NSString *fullPath = [(self.currentPath ?: @"/") stringByAppendingPathComponent:item[@"name"]];
        [self.connectionManager afcDeleteFile:fullPath completion:^(NSError *error) {
            completionHandler(error == nil);
            if (!error) [self loadData];
        }];
    }];

    UIContextualAction *renameAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self renameItem:item];
        completionHandler(YES);
    }];
    renameAction.backgroundColor = [UIColor systemOrangeColor];

    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, renameAction]];
}
@end
