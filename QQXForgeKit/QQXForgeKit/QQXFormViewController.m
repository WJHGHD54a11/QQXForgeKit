//
//  QQXFormViewController.m
//  QQXForgeKit
//

#import "QQXFormViewController.h"
#import <PhotosUI/PhotosUI.h>
#import "QQXTheme.h"
#import "QQXLang.h"
#import "QQXStore.h"
#import "QQXCalc.h"

NSString * const QQXFKey = @"key";
NSString * const QQXFTitle = @"title";
NSString * const QQXFType = @"type";
NSString * const QQXFRequired = @"required";
NSString * const QQXFOptions = @"options";
NSString * const QQXFPlaceholder = @"placeholder";
NSString * const QQXFHint = @"hint";

@interface QQXFormViewController () <PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, readwrite, nullable) NSManagedObject *object;
@property (nonatomic, copy) NSArray<NSDictionary *> *fields;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *controls;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *choices;     // choice key -> NSNumber index
@property (nonatomic, copy, nullable) NSString *photoKey;
@property (nonatomic, copy, nullable) NSString *originalPhoto;
@property (nonatomic, copy, nullable) NSString *currentPhoto;
@property (nonatomic, strong) NSMutableArray<NSString *> *pickedPhotos;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UIButton *removePhotoButton;
@property (nonatomic) BOOL finished;
@end

@implementation QQXFormViewController

- (instancetype)initWithTitle:(NSString *)title object:(NSManagedObject *)object fields:(NSArray<NSDictionary *> *)fields {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = title;
        _object = object;
        _fields = [fields copy];
        _controls = [NSMutableDictionary dictionary];
        _choices = [NSMutableDictionary dictionary];
        _pickedPhotos = [NSMutableArray array];
    }
    return self;
}

- (void)presentFrom:(UIViewController *)host {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self];
    nav.modalInPresentation = !self.readOnly; // avoid losing edits with an accidental swipe
    [host presentViewController:nav animated:YES completion:nil];
}

- (id)initialValue:(NSString *)key {
    if (self.object) return [self.object valueForKey:key];
    return self.initialValues[key];
}

#pragma mark - UI

- (void)viewDidLoad {
    [super viewDidLoad];
    UIStackView *stack = [QQXTheme scrollStackIn:self];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.readOnly ? QL(@"common.close") : QL(@"common.cancel")
                                                                             style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
    if (!self.readOnly) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.saveTitle ?: QL(@"common.save")
                                                                                  style:UIBarButtonItemStyleDone target:self action:@selector(saveTapped)];
    }
    if (self.headerNote.length) {
        UILabel *n = [QQXTheme labelWithSize:13 weight:UIFontWeightRegular color:[QQXTheme text2]];
        n.text = self.headerNote;
        [stack addArrangedSubview:n];
    }
    for (NSDictionary *f in self.fields) {
        UIView *v = [self buildField:f];
        if (v) [stack addArrangedSubview:v];
    }
    if (!self.readOnly && !self.object) {
        UILabel *req = [QQXTheme labelWithSize:12 weight:UIFontWeightRegular color:[QQXTheme text2]];
        req.text = QL(@"form.requiredHint");
        [stack addArrangedSubview:req];
    }
    if (self.deleteTitle && self.deleteHandler && self.object && !self.readOnly) {
        UIButton *del = [QQXTheme buttonWithTitle:self.deleteTitle style:QQXButtonStyleDestructive];
        [del addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        [stack setCustomSpacing:28 afterView:stack.arrangedSubviews.lastObject];
        [stack addArrangedSubview:del];
    }
}

- (NSString *)caption:(NSDictionary *)f {
    NSString *t = f[QQXFTitle];
    return [f[QQXFRequired] boolValue] && !self.readOnly ? [t stringByAppendingString:@" *"] : t;
}

- (UIView *)buildField:(NSDictionary *)f {
    NSString *key = f[QQXFKey];
    QQXFieldType type = [f[QQXFType] integerValue];
    id value = [self initialValue:key];
    UIView *control = nil;
    switch (type) {
        case QQXFieldText:
        case QQXFieldNumber: {
            UITextField *t = [QQXTheme fieldWithPlaceholder:f[QQXFPlaceholder]];
            t.text = [value isKindOfClass:[NSString class]] ? value : ([value respondsToSelector:@selector(stringValue)] ? [value stringValue] : nil);
            if (type == QQXFieldNumber) t.keyboardType = UIKeyboardTypeDecimalPad;
            t.autocapitalizationType = UITextAutocapitalizationTypeSentences;
            t.enabled = !self.readOnly;
            control = t;
            break;
        }
        case QQXFieldMultiline: {
            UITextView *t = [QQXTheme textView];
            t.text = value;
            t.editable = !self.readOnly;
            control = t;
            break;
        }
        case QQXFieldDate:
        case QQXFieldDateTime: {
            UIDatePicker *d = [self datePicker];
            if (type == QQXFieldDateTime) d.datePickerMode = UIDatePickerModeDateAndTime;
            d.date = value ?: [NSDate date];
            control = d;
            break;
        }
        case QQXFieldOptionalDate: {
            UIDatePicker *d = [self datePicker];
            d.date = value ?: [NSDate date];
            d.enabled = value != nil && !self.readOnly;
            UISwitch *s = [[UISwitch alloc] init];
            s.on = value != nil;
            s.enabled = !self.readOnly;
            __weak UIDatePicker *wd = d;
            [s addAction:[UIAction actionWithHandler:^(UIAction *a) { wd.enabled = ((UISwitch *)a.sender).isOn; }] forControlEvents:UIControlEventValueChanged];
            UILabel *l = [QQXTheme labelWithSize:15 weight:UIFontWeightRegular color:[QQXTheme text]];
            l.text = QL(@"form.setDate");
            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[s, l, d]];
            row.spacing = 10;
            row.alignment = UIStackViewAlignmentCenter;
            self.controls[[key stringByAppendingString:@".switch"]] = s;
            self.controls[key] = d;
            return [QQXTheme blockWithTitle:[self caption:f] control:row];
        }
        case QQXFieldChoice: {
            NSArray *opts = f[QQXFOptions];
            NSArray *objs = self.choiceObjects[key];
            NSInteger idx = objs ? (NSInteger)[objs indexOfObject:value ?: [NSNull null]] : [value integerValue];
            if (idx < 0 || idx >= (NSInteger)opts.count) idx = 0;
            self.choices[key] = @(idx);
            control = [self choiceButtonForKey:key options:opts];
            break;
        }
        case QQXFieldSwitch: {
            UISwitch *s = [[UISwitch alloc] init];
            s.on = [value boolValue];
            s.enabled = !self.readOnly;
            UILabel *l = [QQXTheme labelWithSize:15 weight:UIFontWeightRegular color:[QQXTheme text]];
            l.text = f[QQXFTitle];
            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[l, s]];
            row.alignment = UIStackViewAlignmentCenter;
            self.controls[key] = s;
            return row;
        }
        case QQXFieldPhoto:
            return [self photoBlock:f value:value];
    }
    self.controls[key] = control;
    UIStackView *block = [QQXTheme blockWithTitle:[self caption:f] control:control];
    if ([f[QQXFHint] length]) {
        UILabel *h = [QQXTheme labelWithSize:12 weight:UIFontWeightRegular color:[QQXTheme text2]];
        h.text = f[QQXFHint];
        [block addArrangedSubview:h];
    }
    return block;
}

- (UIDatePicker *)datePicker {
    UIDatePicker *d = [[UIDatePicker alloc] init];
    d.datePickerMode = UIDatePickerModeDate;
    d.preferredDatePickerStyle = UIDatePickerStyleCompact;
    d.locale = [QQXLang locale];
    d.tintColor = [QQXTheme accent];
    d.enabled = !self.readOnly;
    d.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    return d;
}

- (UIButton *)choiceButtonForKey:(NSString *)key options:(NSArray<NSString *> *)opts {
    UIButton *b = [QQXTheme menuButton];
    b.enabled = !self.readOnly;
    __weak typeof(self) ws = self;
    [QQXTheme configureMenu:b options:opts selected:[self.choices[key] integerValue] handler:^(NSInteger i) {
        ws.choices[key] = @(i);
    }];
    return b;
}

#pragma mark - Photo

- (UIView *)photoBlock:(NSDictionary *)f value:(NSString *)value {
    self.photoKey = f[QQXFKey];
    self.originalPhoto = value.length ? value : nil;
    self.currentPhoto = self.originalPhoto;

    self.photoView = [[UIImageView alloc] init];
    self.photoView.contentMode = UIViewContentModeScaleAspectFit;
    self.photoView.backgroundColor = [QQXTheme field];
    self.photoView.layer.cornerRadius = 8;
    self.photoView.clipsToBounds = YES;
    self.photoView.isAccessibilityElement = YES;
    self.photoView.accessibilityLabel = f[QQXFTitle];
    [self.photoView.heightAnchor constraintEqualToConstant:190].active = YES;

    UIStackView *buttons = [[UIStackView alloc] init];
    buttons.spacing = 8;
    buttons.distribution = UIStackViewDistributionFillEqually;
    if (!self.readOnly) {
        UIButton *lib = [QQXTheme buttonWithTitle:QL(@"photo.library") style:QQXButtonStyleSecondary];
        [lib addTarget:self action:@selector(pickPhoto) forControlEvents:UIControlEventTouchUpInside];
        [buttons addArrangedSubview:lib];
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
            UIButton *cam = [QQXTheme buttonWithTitle:QL(@"photo.camera") style:QQXButtonStyleSecondary];
            [cam addTarget:self action:@selector(takePhoto) forControlEvents:UIControlEventTouchUpInside];
            [buttons addArrangedSubview:cam];
        }
        self.removePhotoButton = [QQXTheme buttonWithTitle:QL(@"photo.remove") style:QQXButtonStyleDestructive];
        [self.removePhotoButton addTarget:self action:@selector(removePhoto) forControlEvents:UIControlEventTouchUpInside];
        [buttons addArrangedSubview:self.removePhotoButton];
    }
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[self.photoView, buttons]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 8;
    [self refreshPhoto];
    return [QQXTheme blockWithTitle:f[QQXFTitle] control:s];
}

- (void)refreshPhoto {
    UIImage *img = [[QQXStore shared] photoNamed:self.currentPhoto];
    self.photoView.image = img;
    self.photoView.hidden = (img == nil && self.currentPhoto == nil);
    self.removePhotoButton.hidden = (self.currentPhoto == nil);
    if (self.currentPhoto && !img) {
        // Reference exists but the file is gone: say so instead of showing an empty frame.
        self.photoView.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
        self.photoView.tintColor = [QQXTheme amber];
        self.photoView.contentMode = UIViewContentModeCenter;
        self.photoView.accessibilityValue = QL(@"photo.missing");
    } else {
        self.photoView.contentMode = UIViewContentModeScaleAspectFit;
        self.photoView.accessibilityValue = nil;
    }
}

- (void)pickPhoto {
    PHPickerConfiguration *c = [[PHPickerConfiguration alloc] init];
    c.filter = [PHPickerFilter imagesFilter];
    c.selectionLimit = 1;
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:c];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)takePhoto {
    UIImagePickerController *p = [[UIImagePickerController alloc] init];
    p.sourceType = UIImagePickerControllerSourceTypeCamera;
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)removePhoto {
    self.currentPhoto = nil;
    [self refreshPhoto];
}

- (void)usePickedImage:(UIImage *)image {
    NSString *err = nil;
    NSString *name = [[QQXStore shared] savePhoto:image error:&err];
    if (!name) { [QQXTheme alertIn:self title:QL(@"common.error") message:err]; return; }
    [self.pickedPhotos addObject:name];
    self.currentPhoto = name;
    [self refreshPhoto];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *p = results.firstObject.itemProvider;
    if (!p) return;
    if (![p canLoadObjectOfClass:[UIImage class]]) { [QQXTheme alertIn:self title:QL(@"common.error") message:QL(@"photo.loadFailed")]; return; }
    __weak typeof(self) ws = self;
    [p loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> obj, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([(NSObject *)obj isKindOfClass:[UIImage class]]) [ws usePickedImage:(UIImage *)obj];
            else if (ws) [QQXTheme alertIn:ws title:QL(@"common.error") message:QL(@"photo.loadFailed")];
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) [self usePickedImage:img];
    else [QQXTheme alertIn:self title:QL(@"common.error") message:QL(@"photo.loadFailed")];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Save / cancel

/// key -> value (NSNull when empty). Returns nil and sets error when a field is invalid.
- (NSDictionary *)collect:(NSString **)error {
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    for (NSDictionary *f in self.fields) {
        NSString *key = f[QQXFKey];
        QQXFieldType type = [f[QQXFType] integerValue];
        id value = [NSNull null];
        switch (type) {
            case QQXFieldText:
            case QQXFieldNumber: {
                NSString *s = [QQXTheme trim:((UITextField *)self.controls[key]).text];
                if (type == QQXFieldNumber && s.length) {
                    double d;
                    NSString *e = nil;
                    if (![QQXCalc parse:s value:&d error:&e]) {
                        if (error) *error = [NSString stringWithFormat:@"%@: %@", f[QQXFTitle], e];
                        return nil;
                    }
                }
                if (s.length) value = s;
                break;
            }
            case QQXFieldMultiline: {
                NSString *s = [QQXTheme trim:((UITextView *)self.controls[key]).text];
                if (s.length) value = s;
                break;
            }
            case QQXFieldDate:
            case QQXFieldDateTime:
                value = ((UIDatePicker *)self.controls[key]).date;
                break;
            case QQXFieldOptionalDate:
                if (((UISwitch *)self.controls[[key stringByAppendingString:@".switch"]]).isOn) value = ((UIDatePicker *)self.controls[key]).date;
                break;
            case QQXFieldChoice: {
                NSInteger idx = [self.choices[key] integerValue];
                NSArray *objs = self.choiceObjects[key];
                value = objs ? (idx < (NSInteger)objs.count ? objs[idx] : [NSNull null]) : @(idx);
                break;
            }
            case QQXFieldSwitch:
                value = @(((UISwitch *)self.controls[key]).isOn);
                break;
            case QQXFieldPhoto:
                if (self.currentPhoto) value = self.currentPhoto;
                break;
        }
        if ([f[QQXFRequired] boolValue] && value == [NSNull null]) {
            if (error) *error = [NSString stringWithFormat:QL(@"err.required"), f[QQXFTitle]];
            return nil;
        }
        v[key] = value;
    }
    return v;
}

- (void)saveTapped {
    [self.view endEditing:YES];
    NSString *err = nil;
    NSDictionary *values = [self collect:&err];
    if (values && self.validate) err = self.validate(values);
    if (!values || err) { [QQXTheme alertIn:self title:QL(@"common.checkInput") message:err]; return; }

    BOOL created = NO;
    if (!self.object && self.makeObject) { self.object = self.makeObject(); created = YES; }
    NSManagedObject *o = self.object;
    NSMutableDictionary *previous = [NSMutableDictionary dictionary];
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *k, id val, BOOL *stop) {
        previous[k] = [o valueForKey:k] ?: [NSNull null];
        [o setValue:(val == [NSNull null] ? nil : val) forKey:k];
    }];
    id previousUpdated = [o valueForKey:@"updatedAt"];
    [o setValue:[NSDate date] forKey:@"updatedAt"];

    BOOL ok = self.commit ? self.commit(&err) : [[QQXStore shared] save:&err];
    if (!ok) {
        // Restore the in-memory object so nothing half-applied leaks into other screens.
        if (created) {
            if (!o.isDeleted && o.managedObjectContext) [o.managedObjectContext deleteObject:o];
            self.object = nil;
        } else if (!o.isDeleted && o.managedObjectContext) {
            [previous enumerateKeysAndObjectsUsingBlock:^(NSString *k, id val, BOOL *stop) {
                [o setValue:(val == [NSNull null] ? nil : val) forKey:k];
            }];
            [o setValue:previousUpdated forKey:@"updatedAt"];
        }
        [QQXTheme alertIn:self title:QL(@"common.error") message:err ?: QL(@"err.saveFailed")];
        return;
    }
    // Saved: drop files that are no longer referenced (replaced original, abandoned picks).
    if (self.deferPhotoCleanup) { [self finish:YES]; return; }
    QQXStore *store = [QQXStore shared];
    if (self.originalPhoto && ![self.originalPhoto isEqualToString:self.currentPhoto ?: @""]) [store removePhotoIfUnused:self.originalPhoto];
    for (NSString *p in self.pickedPhotos) {
        if (![p isEqualToString:self.currentPhoto ?: @""]) [store removePhotoIfUnused:p];
    }
    [self finish:YES];
}

- (void)cancelTapped {
    // Discarded picks were never referenced by a saved record.
    if (!self.deferPhotoCleanup) for (NSString *p in self.pickedPhotos) [[QQXStore shared] removePhotoIfUnused:p];
    [self finish:NO];
}

- (void)deleteTapped {
    self.deleteHandler(self);
}

- (void)finish:(BOOL)saved {
    if (self.finished) return;
    self.finished = YES;
    void (^done)(BOOL) = self.onFinish;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (done) done(saved);
    }];
}

@end
