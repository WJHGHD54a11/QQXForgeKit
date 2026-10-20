//
//  QQXReport.m
//  QQXForgeKit
//

#import "QQXReport.h"
#import "QQXLang.h"
#import "QQXTheme.h"
#import "QQXStore.h"

// A4 in points.
static const CGFloat kPageW = 595.2, kPageH = 841.8, kMargin = 40, kHeaderH = 54, kFooterH = 34;

static UIColor *RGB(CGFloat r, CGFloat g, CGFloat b) { return [UIColor colorWithRed:r / 255 green:g / 255 blue:b / 255 alpha:1]; }

@interface QQXReport ()
@property (nonatomic, strong) UIGraphicsPDFRendererContext *ctx;
@property (nonatomic) CGFloat y;
@property (nonatomic) NSInteger page;
@property (nonatomic, copy) NSString *headerTitle;
@property (nonatomic, copy) NSString *generatedText;
@end

@implementation QQXReport

#pragma mark - Validation

+ (NSArray<NSString *> *)missingDataForInspection:(NSManagedObject *)inspection {
    NSMutableArray *m = [NSMutableArray array];
    if (inspection.isDeleted || inspection.managedObjectContext == nil) { [m addObject:QL(@"pdf.err.deleted")]; return m; }
    if (inspection.objectID.isTemporaryID || inspection.hasChanges) [m addObject:QL(@"pdf.err.unsaved")];
    if (![inspection valueForKey:@"equipment"]) [m addObject:QL(@"pdf.err.noEquipment")];
    if ([QQXTheme trim:[inspection valueForKey:@"title"]].length == 0) [m addObject:QL(@"pdf.err.noTitle")];
    if ([[inspection valueForKey:@"items"] count] == 0) [m addObject:QL(@"pdf.err.noItems")];
    return m;
}

#pragma mark - Generation

+ (NSURL *)generateForInspection:(NSManagedObject *)inspection includePhotos:(BOOL)includePhotos error:(NSString **)error {
    NSArray *missing = [self missingDataForInspection:inspection];
    if (missing.count) {
        if (error) *error = [missing componentsJoinedByString:@"\n"];
        return nil;
    }
    QQXReport *r = [[QQXReport alloc] init];
    return [r render:inspection photos:includePhotos error:error];
}

- (NSURL *)render:(NSManagedObject *)insp photos:(BOOL)includePhotos error:(NSString **)error {
    NSManagedObject *eq = [insp valueForKey:@"equipment"];
    NSArray *items = [[QQXStore shared] sorted:[insp valueForKey:@"items"] key:@"sortIndex" ascending:YES];
    self.headerTitle = QL(@"pdf.title");
    self.generatedText = [NSString stringWithFormat:@"%@: %@", QL(@"pdf.generated"), [QQXTheme dateTime:[NSDate date]]];

    // Asset tag reduced to letters/digits so it is safe inside a file name.
    NSString *rawTag = [eq valueForKey:@"assetTag"] ?: @"report";
    NSString *tag = [[rawTag componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]]
                     componentsJoinedByString:@"-"];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"yyyyMMdd-HHmm";
    NSString *file = [NSString stringWithFormat:@"QQXForgeKit-Inspection-%@-%@.pdf", tag, [df stringFromDate:[NSDate date]]];
    NSURL *dir = [[NSFileManager defaultManager].temporaryDirectory URLByAppendingPathComponent:@"Reports" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *url = [dir URLByAppendingPathComponent:file];

    UIGraphicsPDFRendererFormat *fmt = [UIGraphicsPDFRendererFormat defaultFormat];
    fmt.documentInfo = @{(__bridge NSString *)kCGPDFContextTitle: QL(@"pdf.title"),
                         (__bridge NSString *)kCGPDFContextCreator: @"QQXForgeKit"};
    UIGraphicsPDFRenderer *renderer = [[UIGraphicsPDFRenderer alloc] initWithBounds:CGRectMake(0, 0, kPageW, kPageH) format:fmt];
    NSError *e = nil;
    BOOL ok = [renderer writePDFToURL:url withActions:^(UIGraphicsPDFRendererContext *c) {
        self.ctx = c;
        [self newPage];
        [self drawSummary:insp equipment:eq items:items];
        [self drawItems:items photos:includePhotos];
        [self drawFailures:items];
        [self drawNotes:insp];
    } error:&e];
    self.ctx = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    if (!ok || [attrs fileSize] == 0) {
        NSLog(@"[QQXReport] PDF failed: %@", e);
        if (error) *error = QL(@"pdf.err.render");
        return nil;
    }
    return url;
}

#pragma mark - Page furniture

- (CGFloat)contentW { return kPageW - kMargin * 2; }
- (CGFloat)bottom { return kPageH - kMargin - kFooterH; }

- (void)newPage {
    [self.ctx beginPage];
    self.page += 1;
    // Header: brand mark + report title, identical on every page.
    [RGB(14, 16, 19) setFill];
    UIRectFill(CGRectMake(0, 0, kPageW, kHeaderH));
    [RGB(34, 211, 238) setFill];
    UIRectFill(CGRectMake(0, kHeaderH, kPageW, 2));
    UIBezierPath *mark = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(kMargin, 15, 24, 24) cornerRadius:5];
    [mark fill];
    [@"QX" drawInRect:CGRectMake(kMargin, 20, 24, 14) withAttributes:[self attrs:9 bold:YES color:RGB(14, 16, 19) align:NSTextAlignmentCenter]];
    [@"QQXForgeKit" drawAtPoint:CGPointMake(kMargin + 32, 13) withAttributes:[self attrs:13 bold:YES color:UIColor.whiteColor align:NSTextAlignmentLeft]];
    [self.headerTitle drawAtPoint:CGPointMake(kMargin + 32, 30) withAttributes:[self attrs:9 bold:NO color:RGB(180, 186, 194) align:NSTextAlignmentLeft]];
    [self.generatedText drawInRect:CGRectMake(kPageW / 2, 30, kPageW / 2 - kMargin, 14)
                    withAttributes:[self attrs:8 bold:NO color:RGB(180, 186, 194) align:NSTextAlignmentRight]];
    // Footer: page number. Total page count is unknown while streaming, so "Page n" is used.
    [RGB(210, 214, 220) setFill];
    UIRectFill(CGRectMake(kMargin, kPageH - kMargin - 14, [self contentW], 0.5));
    NSString *pg = [NSString stringWithFormat:QL(@"pdf.page"), (long)self.page];
    [pg drawInRect:CGRectMake(kMargin, kPageH - kMargin - 8, [self contentW], 12)
    withAttributes:[self attrs:8 bold:NO color:RGB(110, 116, 124) align:NSTextAlignmentRight]];
    [QL(@"pdf.footer") drawInRect:CGRectMake(kMargin, kPageH - kMargin - 8, [self contentW] * 0.7, 12)
                   withAttributes:[self attrs:8 bold:NO color:RGB(110, 116, 124) align:NSTextAlignmentLeft]];
    self.y = kHeaderH + 22;
}

- (void)ensure:(CGFloat)height {
    if (self.y + height > [self bottom]) [self newPage];
}

- (NSDictionary *)attrs:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color align:(NSTextAlignment)align {
    NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
    p.lineBreakMode = NSLineBreakByWordWrapping;
    p.alignment = align;
    // System font falls back to PingFang for CJK glyphs, so Chinese renders correctly.
    return @{NSFontAttributeName: [UIFont systemFontOfSize:size weight:bold ? UIFontWeightSemibold : UIFontWeightRegular],
             NSForegroundColorAttributeName: color,
             NSParagraphStyleAttributeName: p};
}

- (CGFloat)heightOf:(NSString *)s attrs:(NSDictionary *)a width:(CGFloat)w {
    if (s.length == 0) return 0;
    return ceil([s boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
                                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                             attributes:a context:nil].size.height);
}

- (UIColor *)ink   { return RGB(28, 31, 36); }
- (UIColor *)muted { return RGB(104, 110, 118); }

- (UIColor *)resultColor:(NSInteger)r {
    switch (r) {
        case QQXItemResultPass: return RGB(22, 128, 61);
        case QQXItemResultFail: return RGB(200, 40, 52);
        case QQXItemResultNA:   return RGB(104, 110, 118);
        default:                return RGB(176, 106, 0);
    }
}

/// Draws attributed text at the current y, continuing on new pages when it does not fit.
- (void)flow:(NSAttributedString *)s x:(CGFloat)x width:(CGFloat)w bar:(UIColor *)bar {
    if (s.length == 0) return;
    NSTextStorage *ts = [[NSTextStorage alloc] initWithAttributedString:s];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    [ts addLayoutManager:lm];
    NSUInteger done = 0, total = lm.numberOfGlyphs;
    NSInteger guard = 0;
    while (done < total && guard++ < 1000) {
        CGFloat avail = [self bottom] - self.y;
        if (avail < 16) { [self newPage]; continue; }
        NSTextContainer *tc = [[NSTextContainer alloc] initWithSize:CGSizeMake(w, avail)];
        tc.lineFragmentPadding = 0;
        [lm addTextContainer:tc];
        NSRange g = [lm glyphRangeForTextContainer:tc];
        if (g.length == 0) { [self newPage]; continue; }
        CGFloat h = ceil([lm usedRectForTextContainer:tc].size.height);
        if (bar) { [bar setFill]; UIRectFill(CGRectMake(kMargin, self.y, 3, h)); }
        [lm drawGlyphsForGlyphRange:g atPoint:CGPointMake(x, self.y)];
        self.y += h;
        done = NSMaxRange(g);
    }
}

- (NSAttributedString *)str:(NSString *)s size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)c {
    return [[NSAttributedString alloc] initWithString:s ?: @"" attributes:[self attrs:size bold:bold color:c align:NSTextAlignmentLeft]];
}

/// "Label: value" with a muted label.
- (NSAttributedString *)pair:(NSString *)label value:(NSString *)value {
    NSMutableAttributedString *m = [[NSMutableAttributedString alloc] initWithAttributedString:
                                    [self str:[label stringByAppendingString:@": "] size:10 bold:YES color:[self muted]]];
    [m appendAttributedString:[self str:value size:10 bold:NO color:[self ink]]];
    return m;
}

- (void)section:(NSString *)title {
    [self ensure:60];
    self.y += 10;
    [title drawAtPoint:CGPointMake(kMargin, self.y) withAttributes:[self attrs:13 bold:YES color:[self ink] align:NSTextAlignmentLeft]];
    self.y += 20;
    [RGB(34, 211, 238) setFill];
    UIRectFill(CGRectMake(kMargin, self.y, 36, 2));
    [RGB(220, 224, 229) setFill];
    UIRectFill(CGRectMake(kMargin + 36, self.y + 0.5, [self contentW] - 36, 1));
    self.y += 10;
}

- (void)row:(NSString *)label value:(NSString *)value {
    NSDictionary *la = [self attrs:10 bold:YES color:[self muted] align:NSTextAlignmentLeft];
    CGFloat lw = 132;
    CGFloat lh = [self heightOf:label attrs:la width:lw];
    [self ensure:MAX(lh, 14)];
    CGFloat start = self.y;
    NSInteger page = self.page;
    [label drawInRect:CGRectMake(kMargin, start, lw, lh) withAttributes:la];
    [self flow:[self str:value size:10 bold:NO color:[self ink]] x:kMargin + lw + 8 width:[self contentW] - lw - 8 bar:nil];
    if (self.page == page) self.y = MAX(self.y, start + lh);
    self.y += 5;
}

- (void)drawSummary:(NSManagedObject *)insp equipment:(NSManagedObject *)eq items:(NSArray *)items {
    NSString *title = [QQXTheme trim:[insp valueForKey:@"title"]];
    [self flow:[self str:title size:18 bold:YES color:[self ink]] x:kMargin width:[self contentW] bar:nil];
    self.y += 8;

    [self section:QL(@"pdf.sec.equipment")];
    [self row:QL(@"f.eqName") value:[eq valueForKey:@"name"] ?: @""];
    [self row:QL(@"f.assetTag") value:[eq valueForKey:@"assetTag"] ?: @""];
    NSString *model = [QQXTheme trim:[eq valueForKey:@"model"]];
    [self row:QL(@"f.model") value:model.length ? model : QL(@"common.notProvided")];
    NSString *loc = [QQXTheme trim:[eq valueForKey:@"location"]];
    if (loc.length) [self row:QL(@"f.location") value:loc];
    NSString *mfr = [QQXTheme trim:[eq valueForKey:@"manufacturer"]];
    if (mfr.length) [self row:QL(@"f.manufacturer") value:mfr];

    [self section:QL(@"pdf.sec.inspection")];
    [self row:QL(@"f.inspTitle") value:title];
    [self row:QL(@"f.inspDate") value:[QQXTheme date:[insp valueForKey:@"date"]]];
    NSString *who = [QQXTheme trim:[insp valueForKey:@"inspector"]];
    [self row:QL(@"f.inspector") value:who.length ? who : QL(@"common.notProvided")];
    NSInteger status = [[insp valueForKey:@"status"] integerValue];
    [self row:QL(@"f.status") value:[QQXTheme inspectionStatusText:status]];
    if (status == QQXInspectionStatusComplete) [self row:QL(@"f.completedAt") value:[QQXTheme dateTime:[insp valueForKey:@"completedAt"]]];
    [self row:QL(@"pdf.generated") value:[QQXTheme dateTime:[NSDate date]]];

    NSInteger pass = 0, fail = 0, na = 0, pending = 0;
    for (NSManagedObject *i in items) {
        switch ([[i valueForKey:@"result"] integerValue]) {
            case QQXItemResultPass: pass++; break;
            case QQXItemResultFail: fail++; break;
            case QQXItemResultNA: na++; break;
            default: pending++; break;
        }
    }
    NSString *counts = [NSString stringWithFormat:@"%@ %ld · %@ %ld · %@ %ld · %@ %ld · %@ %ld",
                        QL(@"pdf.total"), (long)items.count, QL(@"result.pass"), (long)pass, QL(@"result.fail"), (long)fail,
                        QL(@"result.na"), (long)na, QL(@"result.pending"), (long)pending];
    [self row:QL(@"pdf.results") value:counts];
    if (status != QQXInspectionStatusComplete) {
        self.y += 2;
        [self flow:[self str:QL(@"pdf.draftNote") size:10 bold:YES color:[self resultColor:QQXItemResultPending]]
                 x:kMargin width:[self contentW] bar:nil];
    }
}

- (CGSize)photoSize:(UIImage *)img {
    CGFloat maxW = 240, maxH = 170;
    if (img.size.width <= 0 || img.size.height <= 0) return CGSizeZero;
    // Aspect-fit, never upscale.
    CGFloat s = MIN(1.0, MIN(maxW / img.size.width, maxH / img.size.height));
    return CGSizeMake(floor(img.size.width * s), floor(img.size.height * s));
}

- (void)drawItems:(NSArray<NSManagedObject *> *)items photos:(BOOL)includePhotos {
    [self section:QL(@"pdf.sec.items")];
    CGFloat indent = kMargin + 12, w = [self contentW] - 12, badgeW = 96;
    [items enumerateObjectsUsingBlock:^(NSManagedObject *it, NSUInteger idx, BOOL *stop) {
        NSInteger res = [[it valueForKey:@"result"] integerValue];
        NSString *head = [NSString stringWithFormat:@"%lu. %@", (unsigned long)idx + 1, [it valueForKey:@"text"] ?: @""];
        NSAttributedString *headStr = [self str:head size:11 bold:YES color:[self ink]];
        NSMutableArray<NSAttributedString *> *lines = [NSMutableArray array];
        NSString *mv = [QQXTheme trim:[it valueForKey:@"measureValue"]];
        if (mv.length) {
            NSString *unit = [QQXTheme trim:[it valueForKey:@"measureUnit"]];
            [lines addObject:[self pair:QL(@"f.measurement") value:unit.length ? [NSString stringWithFormat:@"%@ %@", mv, unit] : mv]];
        }
        NSString *notes = [QQXTheme trim:[it valueForKey:@"notes"]];
        if (notes.length) [lines addObject:[self pair:QL(@"f.notes") value:notes]];
        if ([it valueForKey:@"maintenanceRecord"]) [lines addObject:[self str:QL(@"pdf.converted") size:9 bold:NO color:[self muted]]];

        UIImage *img = nil;
        BOOL photoMissing = NO;
        NSString *photo = [it valueForKey:@"photo"];
        if (includePhotos && photo.length && [[it valueForKey:@"photoInReport"] boolValue]) {
            img = [[QQXStore shared] photoNamed:photo];
            photoMissing = (img == nil);
            if (photoMissing) [lines addObject:[self str:QL(@"pdf.photoMissing") size:9 bold:NO color:[self resultColor:QQXItemResultPending]]];
        }
        CGSize ps = img ? [self photoSize:img] : CGSizeZero;

        // Measure the whole block so an item stays on one page whenever it can.
        CGFloat h = [headStr boundingRectWithSize:CGSizeMake(w - badgeW - 8, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.height + 6;
        for (NSAttributedString *l in lines) {
            h += ceil([l boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin context:nil].size.height) + 3;
        }
        if (img) h += ps.height + 8;
        h += 12;
        CGFloat pageSpace = [self bottom] - (kHeaderH + 22);
        [self ensure:MIN(h, pageSpace)];

        UIColor *rc = [self resultColor:res];
        UIColor *bar = res == QQXItemResultFail ? rc : nil;
        if (res == QQXItemResultFail) {
            [[rc colorWithAlphaComponent:0.06] setFill];
            UIRectFill(CGRectMake(kMargin, self.y - 3, [self contentW], MIN(h, [self bottom] - self.y + 3)));
        }
        // Result badge: text + colour so it reads in grayscale prints too.
        NSString *badge = [[QQXTheme resultText:res] uppercaseStringWithLocale:[QQXLang locale]];
        CGRect br = CGRectMake(kMargin + [self contentW] - badgeW, self.y, badgeW, 16);
        [[rc colorWithAlphaComponent:0.12] setFill];
        UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:br cornerRadius:4];
        [bp fill];
        [rc setStroke];
        bp.lineWidth = 0.8;
        [bp stroke];
        [badge drawInRect:CGRectInset(br, 2, 2.5) withAttributes:[self attrs:8.5 bold:YES color:rc align:NSTextAlignmentCenter]];

        [self flow:headStr x:indent width:w - badgeW - 8 bar:bar];
        self.y = MAX(self.y, CGRectGetMaxY(br)) + 4;
        for (NSAttributedString *l in lines) {
            [self flow:l x:indent width:w bar:bar];
            self.y += 3;
        }
        if (img) {
            [self ensure:ps.height + 8];
            [img drawInRect:CGRectMake(indent, self.y + 2, ps.width, ps.height)];
            self.y += ps.height + 8;
        }
        self.y += 6;
        [RGB(228, 231, 235) setFill];
        UIRectFill(CGRectMake(kMargin, self.y - 3, [self contentW], 0.5));
        self.y += 3;
    }];
}

- (void)drawFailures:(NSArray<NSManagedObject *> *)items {
    [self section:QL(@"pdf.sec.failures")];
    NSInteger n = 0;
    for (NSManagedObject *it in items) {
        if ([[it valueForKey:@"result"] integerValue] != QQXItemResultFail) continue;
        n++;
        NSMutableAttributedString *m = [[NSMutableAttributedString alloc] initWithAttributedString:
                                        [self str:[NSString stringWithFormat:@"• %@", [it valueForKey:@"text"] ?: @""] size:10 bold:YES color:[self resultColor:QQXItemResultFail]]];
        NSString *notes = [QQXTheme trim:[it valueForKey:@"notes"]];
        [m appendAttributedString:[self str:[@"\n" stringByAppendingString:notes.length ? notes : QL(@"pdf.noItemNotes")] size:10 bold:NO color:[self ink]]];
        [self ensure:30];
        [self flow:m x:kMargin + 12 width:[self contentW] - 12 bar:[self resultColor:QQXItemResultFail]];
        self.y += 8;
    }
    if (n == 0) {
        [self flow:[self str:QL(@"pdf.noFailures") size:10 bold:NO color:[self muted]] x:kMargin width:[self contentW] bar:nil];
    }
}

- (void)drawNotes:(NSManagedObject *)insp {
    [self section:QL(@"pdf.sec.notes")];
    NSString *notes = [QQXTheme trim:[insp valueForKey:@"notes"]];
    [self flow:[self str:notes.length ? notes : QL(@"common.notProvided") size:10 bold:NO color:notes.length ? [self ink] : [self muted]]
             x:kMargin width:[self contentW] bar:nil];
    self.y += 14;
    [self flow:[self str:QL(@"pdf.disclaimer") size:8.5 bold:NO color:[self muted]] x:kMargin width:[self contentW] bar:nil];
}

@end
