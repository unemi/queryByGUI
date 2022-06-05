//
//  main.m
//  queryByGUI
//
//  Created by Tatsuo Unemi on 2022/05/23.
//

#import <AppKit/AppKit.h>
#define ALLOC_UNIT 8192
#define PADDING 20
#define SPACING 8
#define EXSPACE 2.5

void error_return(NSString *msg) {
	fprintf(stderr, "%s\n", msg.UTF8String);
	exit(1);
}
NSDateFormatter *make_date_formmater(NSString *format) {
	NSDateFormatter *dtFmt = NSDateFormatter.new;
	dtFmt.dateFormat = format;
	return dtFmt;
}
NSDateFormatter *dateFormat(void) {
	static NSDateFormatter *dtFmt = nil;
	if (dtFmt == nil) dtFmt = make_date_formmater(@"yyyy-MM-dd");
	return dtFmt;
}
NSDate *dateFromString(NSString *str) {
	if ([str isEqualToString:@"today"]) return NSDate.date;
	NSDate *date = [dateFormat() dateFromString:str];
	if (date == nil) error_return([NSString stringWithFormat:
		@"Failed to parse date string:\"%@\".", str]);
	return date;
}
NSDateFormatter *timeFormat(void) {
	static NSDateFormatter *tmFmt = nil;
	if (tmFmt == nil) tmFmt = make_date_formmater(@"HH:mm:ss");
	return tmFmt;
}
NSDate *timeFromString(NSString *str) {
	if ([str isEqualToString:@"now"]) return NSDate.date;
	NSDate *date = [timeFormat() dateFromString:str];
	if (date == nil) error_return([NSString stringWithFormat:
		@"Failed to parse time string:\"%@\".", str]);
	return date;
}

typedef enum { AnchorNone = 0,
	AnchorMin = 1,
	AnchorMax = 2,
	FixedSize = 4,
	AnchorMinMax = (AnchorMin | AnchorMax),
	AnchorAll = (AnchorMin | AnchorMax | FixedSize)
} AnchorType;
typedef struct {
	AnchorType h, v;
} AnchorsInfo;

@interface PlacedInfo : NSObject
@property AnchorsInfo anc;
@property NSView *object;
@property NSString *(^getValueBlock)(id);
@property NSDictionary *properties;
@property (readonly) NSString *name;
@end
@implementation PlacedInfo
- (instancetype)initWithObject:(NSView *)obj block:(NSString *(^)(id))block {
	if ((self = [super init]) == nil) return nil;
	_object = obj;
	_getValueBlock = block;
	return self;
}
+ (PlacedInfo *)infoWithObject:(NSView *)obj block:(NSString *(^)(id))block {
	return [PlacedInfo.alloc initWithObject:obj block:block];
}
- (CGFloat)baselineOffsetFromBottom {
	return self.object.baselineOffsetFromBottom;
}
- (NSRect)frame {
	return [_object alignmentRectForFrame:_object.frame];
}
- (void)setFrame:(NSRect)frame {
	_object.frame = [_object frameForAlignmentRect:frame];
}
- (NSString *)setupName {
	NSString *nm = _properties[@"name"];
	if (nm == nil) {
		if ([_object isMemberOfClass:NSButton.class])
			_name = ((NSButton *)_object).title;
		else _name = _object.class.description;
	} else _name = nm;
	return _name;
}
- (void)placeItInParentView:(NSView *)parent {
	[parent addSubview:_object];
}
#ifdef DEBUG
- (NSString *)description {
	NSRect rct = self.frame;
	return [NSString stringWithFormat:@"%@:%@:(%.1f,%.1f)%.1fx%.1f,%d-%d",self.class,
		_name,rct.origin.x,rct.origin.y,rct.size.width,rct.size.height,_anc.h,_anc.v];
}
#endif
@end

@interface ExtPlacedInfo : PlacedInfo {
	NSRect alignRect;
}
@property NSTextField *titleText;
@property NSControl *extra;
@end
@implementation ExtPlacedInfo
static NSTextField *mk_digits_text(NSDictionary *, NSSlider *);
- (instancetype)initWithObject:(NSView *)obj
	itemInfo:(NSDictionary *)item block:(NSString *(^)(id))block {
	if ((self = [super initWithObject:obj block:block]) == nil) return nil;
	NSRect oRct = [self.object alignmentRectForFrame:self.object.frame];
	NSString *title = item[@"title"];
	if (title != nil) {
		NSTextField *label = [NSTextField labelWithString:title];
		NSRect tRct = [label alignmentRectForFrame:label.frame];
		oRct.origin.x = NSMaxX(tRct) + EXSPACE;
		oRct.origin.y = tRct.origin.y +
			label.baselineOffsetFromBottom - self.object.baselineOffsetFromBottom;
		self.object.frame = [self.object frameForAlignmentRect:oRct];
		_titleText = label;
		alignRect = NSUnionRect(tRct, oRct);
	} else alignRect = oRct;
	NSControl *cntl = (NSControl *)obj;
	NSNumber *num;
	if ((num = item[@"stepper"]) != nil && num.boolValue) {
		NSNumberFormatter *fmt = ((NSTextField *)self.object).formatter;
		NSStepper *stp = NSStepper.new;
		stp.minValue = ((num = item[@"min"]) != nil)? num.doubleValue :
			((num = fmt.minimum) != nil)? num.doubleValue : -1e4;
		stp.maxValue = ((num = item[@"max"]) != nil)? num.doubleValue :
			((num = fmt.maximum) != nil)? num.doubleValue : 1e4;
		if ((num = item[@"value"]) != nil) stp.doubleValue = num.doubleValue;
		if ((num = item[@"increment"]) != nil) stp.increment = num.doubleValue;
		[stp sizeToFit];
		_extra = stp;
	} else if ((num = item[@"digits"]) != nil && num.boolValue) {
		_extra = mk_digits_text(item, (NSSlider *)self.object);
	}
	if (_extra != nil) {
		NSRect tRct = [_extra alignmentRectForFrame:_extra.frame];
		tRct.origin = (NSPoint){NSMaxX(oRct) + EXSPACE,
			oRct.origin.y + round((oRct.size.height - tRct.size.height) / 2.)};
		_extra.frame = [_extra frameForAlignmentRect:tRct];
		_extra.target = cntl;
		cntl.target = _extra;
		_extra.action = cntl.action = @selector(takeDoubleValueFrom:);
		alignRect = NSUnionRect(tRct, alignRect);
	}
	return self;
}
- (CGFloat)baselineOffsetFromBottom {
	return self.object.baselineOffsetFromBottom +
		self.object.frame.origin.y + self.object.alignmentRectInsets.bottom
		- alignRect.origin.y;
}
- (NSRect)frame { return alignRect; }
static void shift_view(NSView *view, NSSize shift) {
	NSPoint pt = view.frame.origin;
	view.frameOrigin = (NSPoint){pt.x + shift.width, pt.y + shift.height};
}
- (void)setFrame:(NSRect)frame {
	NSSize trans = {frame.origin.x - alignRect.origin.x,
			frame.origin.y - alignRect.origin.y},
		resize = {frame.size.width - alignRect.size.width,
			frame.size.height - alignRect.size.height};
	NSRect frm = self.object.frame;
	frm.origin.x += trans.width; frm.origin.y += trans.height;
	frm.size.width += resize.width; frm.size.height += resize.height;
	self.object.frame = frm;
	if (_titleText != nil) shift_view(_titleText, trans);
	if (_extra != nil) {
		trans.width += resize.width;
		shift_view(_extra, trans);
	}
	alignRect = frame;
}
- (void)placeItInParentView:(NSView *)parent {
	[parent addSubview:self.object];
	if (_titleText != nil) [parent addSubview:_titleText];
	if (_extra != nil) [parent addSubview:_extra];
}
@end

@interface Delegate : NSObject <NSTextFieldDelegate> {
	NSMutableArray<NSTextField *> *mandatoryTexts;
}
@property (readonly) NSMutableArray<PlacedInfo *> *controls;
@property NSButton *OKButton;
@end
@implementation Delegate
- (instancetype)init {
	if ((self = [super init]) == nil) return nil;
	mandatoryTexts = NSMutableArray.new;
	_controls = NSMutableArray.new;
	return self;
}
- (void)ok:(NSButton *)sender {
	for (PlacedInfo *item in _controls) {
		NSString *value = item.getValueBlock(item.object);
		printf("%s:%s\n", item.name.UTF8String, value.UTF8String);
	}
	printf("Clicked:%s\n", sender.title.UTF8String);
	[NSApp terminate:nil];
}
- (void)dummyAction:(id)sender {}
- (void)addMandatoryText:(NSTextField *)txt {
	[mandatoryTexts addObject:txt];
	txt.delegate = self;
}
- (void)checkMandatoryTexts {
	if (_OKButton == nil) return;
	BOOL ready = YES;
	for (NSTextField *txt in mandatoryTexts)
		if (txt.stringValue.length == 0) { ready = NO; break; }
	_OKButton.enabled = ready;
}
- (void)controlTextDidEndEditing:(NSNotification *)notification {
	[self checkMandatoryTexts];
}
@end

@interface RadioButtons : NSView
@end
@implementation RadioButtons
- (void)dummyAction:(id)sender {}
@end

Delegate *delegate;

static NSString *get_title(NSDictionary *item) {
	NSString *title = item[@"title"];
	if (title == nil) if ((title = item[@"name"]) == nil) title = @"???";
	return title;
}
static PlacedInfo *mk_placed_info(NSDictionary *item, NSView *obj,
	NSArray<NSString *> *allowedExtra, NSString *(^block)(id)) {
	BOOL hasExtra = NO;
	for (NSString *exKey in allowedExtra)
		if (item[exKey] != nil) { hasExtra = YES; break; }
	return hasExtra?
		[ExtPlacedInfo.alloc initWithObject:obj itemInfo:item block:block] :
		[PlacedInfo infoWithObject:obj block:block];
}
PlacedInfo *mk_push_button(NSDictionary *item, BOOL *buttonIncluded, NSButton **OKBtn) {
	NSString *title = get_title(item);
	NSButton *btn = [NSButton buttonWithTitle:title target:delegate action:@selector(ok:)];
	if ([title isEqualToString:@"Cancel"]) btn.keyEquivalent = @"\033";
	else {
		if ([title isEqualToString:@"OK"]) *OKBtn = btn;
		*buttonIncluded = YES;
	}
	return [PlacedInfo infoWithObject:btn block:nil];
}
PlacedInfo *mk_checkbox(NSDictionary *item) {
	NSString *title = get_title(item);
	NSButton *btn = [NSButton checkboxWithTitle:title
		target:delegate action:@selector(dummyAction:)];
	NSString *str;
	if ((str = item[@"state"]) != nil) btn.state =
		[str isEqualTo:@"on"]? NSControlStateValueOn :
		[str isEqualTo:@"mixed"]? NSControlStateValueMixed :
			NSControlStateValueOff;
	if ((str = item[@"allow mixed"]) != nil)
		btn.allowsMixedState = str.boolValue;
	return [PlacedInfo infoWithObject:btn block:^(id btn) {
		switch (((NSButton *)btn).state) {
			case NSControlStateValueOn: return @"on";
			case NSControlStateValueOff: return @"off";
			case NSControlStateValueMixed: return @"mixed";
			default: return @"unknown";
	}}];
}
PlacedInfo *mk_label(NSDictionary *item) {
	NSString *text = item[@"text"];
	if (text == nil) text = @"";
	return [PlacedInfo infoWithObject:[NSTextField labelWithString:text] block:nil];
}
PlacedInfo *mk_text(NSDictionary *item) {
	NSString *text = item[@"text"];
	if (text == nil) text = @"";
	NSTextField *txt = [NSTextField textFieldWithString:text];
	if ((text = item[@"placeholder"]) != nil && [text isKindOfClass:NSString.class])
		txt.placeholderString = text;
	NSNumber *num;
	if ((num = item[@"mandatory"]) != nil && num.boolValue)
		[delegate addMandatoryText:txt];
	[txt sizeToFit];
	return mk_placed_info(item, txt, @[@"title"],
		^(id txt) { return ((NSTextField *)txt).stringValue; });
}
static NSTextField *mk_digits_text(NSDictionary *item, NSSlider *mother) {
	NSInteger intPart = 4, fracPart = 2;
	CGFloat maxV = 1e4, minV = -1e4;
	BOOL isLabel = NO;
	NSNumber *num;
	if (mother != nil) {
		maxV = mother.maxValue;
		minV = mother.minValue;
		isLabel = ((num = item[@"editable"]) != nil && !num.boolValue);
	}
	if ((num = item[@"integer"]) != nil) intPart = num.integerValue;
	if ((num = item[@"fraction"]) != nil) fracPart = num.integerValue;
	NSNumberFormatter *fmt = NSNumberFormatter.new;
	if ((num = item[@"max"]) != nil) maxV = (fmt.maximum = num).doubleValue;
	else if (mother != nil) fmt.maximum = @(maxV);
	if ((num = item[@"min"]) != nil) minV = (fmt.minimum = num).doubleValue;
	else if (mother != nil) fmt.minimum = @(minV);
	fmt.numberStyle = NSNumberFormatterDecimalStyle;
	fmt.maximumIntegerDigits = intPart;
	fmt.maximumFractionDigits = fracPart;
	fmt.minimumFractionDigits = fracPart;
	NSInteger intSmpl = 1;
	for (NSInteger i = 0; i < intPart; i ++) intSmpl *= 10; intSmpl --;
	if (minV < 0.) intSmpl = - intSmpl;
	NSString *sampleStr = [fmt stringFromNumber:@((CGFloat)intSmpl)];
	NSTextField *dgt = isLabel? [NSTextField labelWithString:sampleStr] :
		[NSTextField textFieldWithString:sampleStr];
	dgt.alignment = NSTextAlignmentRight;
	[dgt sizeToFit];
	dgt.formatter = fmt;
	dgt.doubleValue = ((num = item[@"value"]) != nil)? num.doubleValue :
		(minV > 0.)? minV : 0.;
	return dgt;
}
PlacedInfo *mk_digits(NSDictionary *item) {
	return mk_placed_info(item, mk_digits_text(item, nil), @[@"title", @"stepper"],
		^(id dgt) { return @(((NSTextField *)dgt).doubleValue).stringValue; });
}
static PlacedInfo *mk_date_time(NSDictionary *item, NSDatePickerElementFlags elements,
	NSDate *(strToDate)(NSString *), NSDateFormatter *format) {
	NSDatePicker *dtPc = NSDatePicker.new;
	NSString *str;
	dtPc.datePickerElements = elements;
	dtPc.dateValue = ((str = item[@"value"]) != nil)? strToDate(str) : NSDate.date;
	if ((str = item[@"min"]) != nil) dtPc.minDate = strToDate(str);
	if ((str = item[@"max"]) != nil) dtPc.maxDate = strToDate(str);
	[dtPc sizeToFit];
	return mk_placed_info(item, dtPc, @[@"title"], ^(id dt) {
		return [format stringFromDate:((NSDatePicker *)dt).dateValue]; });
}
PlacedInfo *mk_date(NSDictionary *item) {
	return mk_date_time(item, NSDatePickerElementFlagYearMonthDay,
		dateFromString, dateFormat());
}
PlacedInfo *mk_time(NSDictionary *item) {
	return mk_date_time(item, NSDatePickerElementFlagHourMinuteSecond,
		timeFromString, timeFormat());
}
PlacedInfo *mk_slider(NSDictionary *item) {
	NSSlider *sld = NSSlider.new;
	NSNumber *num;
	if ((num = item[@"min"]) != nil) sld.minValue = num.doubleValue;
	if ((num = item[@"max"]) != nil) sld.maxValue = num.doubleValue;
	if ((num = item[@"value"]) != nil) sld.doubleValue = num.doubleValue;
	[sld sizeToFit];
	return mk_placed_info(item, sld, @[@"title", @"digits"],
		^(id sld) { return @([sld doubleValue]).stringValue; });
}
PlacedInfo *mk_popup_button(NSDictionary *item) {
	NSArray<NSString *> *choice = item[@"choice"];
	if (![choice isKindOfClass:NSArray.class] || choice.count == 0) return nil;
	NSPopUpButton *popup = NSPopUpButton.new;
	NSString *selectedTitle = nil;
	for (NSString *entry in choice) {
		NSString *title = entry;
		if ([title hasPrefix:@"*"]) selectedTitle = title = [title substringFromIndex:1];
		[popup addItemWithTitle:title];
	}
	if (selectedTitle != nil) [popup selectItemWithTitle:selectedTitle];
	[popup sizeToFit];
	return mk_placed_info(item, popup, @[@"title"],
		^(id popup) { return ((NSPopUpButton *)popup).titleOfSelectedItem; });
}
PlacedInfo *mk_radio_buttons(NSDictionary *item) {
	NSArray<NSString *> *choice = item[@"choice"];
	if (![choice isKindOfClass:NSArray.class] || choice.count == 0) return nil;
	NSMutableArray<NSButton *> *buttons = [NSMutableArray arrayWithCapacity:choice.count];
	NSNumber *num = item[@"columns"];
	NSInteger nColumns = (num != nil)? num.integerValue : 1;
	NSInteger nRows = (choice.count + nColumns - 1) / nColumns;
	CGFloat btnW[nColumns], btnH[nRows];
	memset(btnW, 0, sizeof(btnW));
	memset(btnH, 0, sizeof(btnH));
	RadioButtons *container = RadioButtons.new;
	BOOL defaultSelection = NO;
	for (NSInteger i = 0; i < choice.count; i ++) {
		NSString *entry = choice[i], *title = entry;
		if ([title hasPrefix:@"*"]) { title = [title substringFromIndex:1]; }
		NSButton *btn = [NSButton radioButtonWithTitle:title
			target:container action:@selector(dummyAction:)];
		if (title != entry) { btn.state = NSControlStateValueOn; defaultSelection = YES; }
		[buttons addObject:btn];
		NSSize sz = btn.frame.size;
		if (btnW[i/nRows] < sz.width) btnW[i/nRows] = sz.width;
		if (btnH[i%nRows] < sz.height) btnH[i%nRows] = sz.height;
	}
	if (!defaultSelection) buttons[0].state = NSControlStateValueOn;
	CGFloat wide = btnW[0], high = btnH[0];
	for (NSInteger i = 1; i < nColumns; i ++) wide += SPACING + btnW[i];
	for (NSInteger i = 1; i < nRows; i ++) high += SPACING + btnH[i];
	container.frame = (NSRect){0, 0, wide, high};
	NSRect btnFrm = {0};
	NSEnumerator *enm = buttons.objectEnumerator;
	for (NSInteger col = 0; col < nColumns; col ++) {
		btnFrm.size.width = btnW[col];
		btnFrm.origin.y = high - btnH[0];
		for (NSInteger row = 0; row < nRows; row ++) {
			btnFrm.size.height = btnH[row];
			NSButton *btn = enm.nextObject;
			if (btn == nil) break;
			btn.frame = btnFrm;
			btnFrm.origin.y -= btnFrm.size.height + SPACING;
			[container addSubview:btn];
		}
		btnFrm.origin.x += btnW[col] + SPACING;
	}
	return [PlacedInfo infoWithObject:container block:^(id view) {
		for (NSButton *btn in ((NSView *)view).subviews)
			if (btn.state == NSControlStateValueOn) return btn.title;
		return @"???";
	}];
}
int main(int argc, const char * argv[]) {
	FILE *input = stdin;
#ifdef DEBUG
	input = fopen("/Users/unemi/Program/Utility/queryByGUI/test.json", "r");
#endif
	size_t bufSize = ALLOC_UNIT, bufRest = bufSize, totalBytes = 0;
	char *buf = malloc(bufSize), *bufPt = buf;
	while(!feof(input)) {
		size_t nChars = fread(bufPt, 1, bufRest, input);
		if ((bufRest -= nChars) <= 0) {
			buf = realloc(buf, (bufSize += ALLOC_UNIT));
			bufRest += ALLOC_UNIT;
		}
		bufPt += nChars;
		totalBytes += nChars;
	}

	@autoreleasepool {
	NSData *data = [NSData dataWithBytesNoCopy:buf length:totalBytes freeWhenDone:YES];
	NSError *error;
	NSDictionary *info = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (info == nil) error_return(error.localizedDescription);
	if (![info isKindOfClass:NSDictionary.class]) error_return(@"Input data is not a dictionary.");
	delegate = Delegate.new;
	NSMutableArray<PlacedInfo *> *elements = NSMutableArray.new;
	NSArray<NSDictionary *> *items = info[@"elements"];
	BOOL buttonIncluded = NO;
	NSButton *OKBtn = nil;
	NSMutableDictionary<NSString *, PlacedInfo *> *infoByName = NSMutableDictionary.new;
	if (items != nil && [items isKindOfClass:NSArray.class]) for (NSDictionary *item in items) {
		if (![item isKindOfClass:NSDictionary.class]) continue;
		NSString *type = item[@"type"];
		if (type == nil) continue;
		PlacedInfo *info = nil;
		if ([type isEqualToString:@"push button"])
			info = mk_push_button(item, &buttonIncluded, &OKBtn);
		else if ([type isEqualToString:@"checkbox"]) info = mk_checkbox(item);
		else if ([type isEqualToString:@"label"]) info = mk_label(item);
		else if ([type isEqualToString:@"text"]) info = mk_text(item);
		else if ([type isEqualToString:@"digits"]) info = mk_digits(item);
		else if ([type isEqualToString:@"date"]) info = mk_date(item);
		else if ([type isEqualToString:@"time"]) info = mk_time(item);
		else if ([type isEqualToString:@"slider"]) info = mk_slider(item);
		else if ([type isEqualToString:@"popup button"]) info = mk_popup_button(item);
		else if ([type isEqualToString:@"radio buttons"]) info = mk_radio_buttons(item);
		else error_return([NSString stringWithFormat:@"Unknown element type: %@.", type]);
		if (info == nil) continue;
		info.properties = item;
		if (info.getValueBlock != nil) [delegate.controls addObject:info];
		[elements addObject:(infoByName[[info setupName]] = info)];
	}
	if (!buttonIncluded) {
		OKBtn = [NSButton buttonWithTitle:@"OK" target:delegate action:@selector(ok:)];
		PlacedInfo *info = [PlacedInfo infoWithObject:OKBtn block:nil];
		info.properties = @{@"right":@"window", @"lower":@"window"};
		[elements addObject:(infoByName[[info setupName]] = info)];
	}
	if (OKBtn != nil) {
		OKBtn.keyEquivalent = @"\r";
		delegate.OKButton = OKBtn;
		[delegate checkMandatoryTexts];
	}
	NSRect rect = {0,0,400,200};
	id value;
	if ((value = info[@"width"]) != nil) rect.size.width = [value doubleValue];
	if ((value = info[@"height"]) != nil) rect.size.height = [value doubleValue];
	NSWindow *window = [NSWindow.alloc initWithContentRect:rect
		styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
	if (info[@"title"] != nil) window.title = info[@"title"];

	NSMutableArray *dependency = NSMutableArray.new;
	PlacedInfo *plc;
	for (PlacedInfo *info in elements) {
		NSRect frame = {PADDING, PADDING, info.frame.size};
		AnchorsInfo anc = {AnchorNone, AnchorNone};
		NSDictionary *elmInfo = info.properties;
		if ((value = elmInfo[@"width"]) != nil) {
			if ([value isKindOfClass:NSNumber.class])
				{ frame.size.width = [value doubleValue]; anc.h |= FixedSize; }
		}
		if ((value = elmInfo[@"height"]) != nil) {
			if ([value isKindOfClass:NSNumber.class])
				{ frame.size.height = [value doubleValue]; anc.v |= FixedSize; }
		}
		if ((value = elmInfo[@"left"]) != nil) {
			if ((plc = infoByName[value]) != nil && (plc.anc.h & AnchorMin)) {
				frame.origin.x = NSMaxX(plc.frame) + SPACING;
				anc.h |= AnchorMin;
			} else if (![value isEqualTo:@"window"]) {
				[dependency addObject:@{@"subject":info,@"target":value,@"attr":@"left"}];
			} else anc.h |= AnchorMin;
		}
		if ((value = elmInfo[@"right"]) != nil && anc.h != (AnchorMin | FixedSize)) {
			CGFloat maxX = -1e10;
			if ([value isEqualTo:@"window"]) maxX = NSMaxX(window.contentView.frame) - PADDING;
			else if ((plc = infoByName[value]) != nil && (plc.anc.h & AnchorMax))
				maxX = plc.frame.origin.x - SPACING;
			else [dependency addObject:@{@"subject":info,@"target":value,@"attr":@"right"}];
			if (maxX != -1e10) {
				if (anc.h & AnchorMin) frame.size.width = maxX - frame.origin.x;
				else frame.origin.x = maxX - frame.size.width;
				anc.h |= AnchorMax;
			}
		}
		if ((value = elmInfo[@"lower"]) != nil) {
			if ((plc = infoByName[value]) != nil && (plc.anc.v & AnchorMin)) {
				frame.origin.y = NSMaxY(plc.frame) + SPACING;
				anc.v |= AnchorMin;
			} else if (![value isEqualTo:@"window"]) {
				[dependency addObject:@{@"subject":info,@"target":value,@"attr":@"lower"}];
			} else anc.v |= AnchorMin;
		}
		if ((value = elmInfo[@"upper"]) != nil && anc.v != (AnchorMin | FixedSize)) {
			CGFloat maxY = -1e10;
			if ([value isEqualTo:@"window"]) maxY = NSMaxY(window.contentView.frame) - PADDING;
			else if ((plc = infoByName[value]) != nil && (plc.anc.v & AnchorMax))
				maxY = plc.frame.origin.y - SPACING;
			else [dependency addObject:@{@"subject":info,@"target":value,@"attr":@"upper"}];
			if (maxY != -1e10) {
				if (anc.v & AnchorMin) frame.size.height = maxY - frame.origin.y;
				else frame.origin.y = maxY - frame.size.height;
				anc.v |= AnchorMax;
			}
		}
		if ((value = elmInfo[@"baseline"]) != nil && (anc.v & (AnchorMin | AnchorMax)) == 0) {
			if ((plc = infoByName[value]) != nil &&
				(plc.anc.v & (AnchorMin | AnchorMax)) == (AnchorMin | AnchorMax)) {
				frame.origin.y = plc.object.frame.origin.y +
					plc.baselineOffsetFromBottom - info.baselineOffsetFromBottom;
				anc.v |= AnchorMin | AnchorMax;
			} else [dependency addObject:@{@"subject":info,@"target":value,@"attr":@"baseline"}];
		}
		NSInteger ancInfo = 0;
		if (elmInfo[@"left"] != nil) ancInfo |= 1;
		if (elmInfo[@"right"] != nil) ancInfo |= 2;
		if (ancInfo == 0) anc.h |= (AnchorMin | FixedSize);
		if (elmInfo[@"width"] == nil) {
			if ((anc.h & (AnchorMin | AnchorMax)) != 0) anc.h |= (AnchorMin | AnchorMax);
			if (ancInfo == 1 || ancInfo == 2) anc.h |= FixedSize;
		}
		if (anc.h == (AnchorMin | FixedSize)) anc.h |= AnchorMax;
		else if (anc.h == (AnchorMax | FixedSize)) anc.h |= AnchorMin;
		ancInfo = 0;
		if (elmInfo[@"lower"] != nil) ancInfo |= 1;
		if (elmInfo[@"upper"] != nil) ancInfo |= 2;
		if (ancInfo == 0 && elmInfo[@"baseline"] == nil) anc.v |= (AnchorMin | FixedSize);
		if (elmInfo[@"height"] == nil) {
			if ((anc.v & (AnchorMin | AnchorMax)) != 0) anc.v |= (AnchorMin | AnchorMax);
			if (ancInfo == 1 || ancInfo == 2) anc.v |= FixedSize;
		}
		if (anc.v == (AnchorMin | FixedSize)) anc.v |= AnchorMax;
		else if (anc.v == (AnchorMax | FixedSize)) anc.v |= AnchorMin;
		info.frame = frame;
		info.anc = anc;
#ifdef DEBUG
		puts([NSString stringWithFormat:@"1stPass %@",info].UTF8String);
#endif
	}
	BOOL reduced = NO;
	do { reduced = NO;
	for (NSInteger i = dependency.count - 1; i >= 0; i --) {
		NSDictionary *item = dependency[i];
		NSString *attr = item[@"attr"];
		PlacedInfo *info = item[@"subject"], *target = infoByName[item[@"target"]];
		if (target == nil) continue;
		NSRect frame = info.frame, tgtFrm = target.frame;
		AnchorsInfo anc = info.anc;
		if ([attr isEqualToString:@"left"] && (target.anc.h & AnchorMax)) {
			CGFloat newX = NSMaxX(tgtFrm) + SPACING;
			if ((anc.h & (AnchorMax | FixedSize)) == AnchorMax)
				frame.size.width += frame.origin.x - newX;
			frame.origin.x = newX;
			anc.h |= AnchorMin; if (anc.h & FixedSize) anc.h |= AnchorMax;
		} else if ([attr isEqualToString:@"right"] && (target.anc.h & AnchorMin)) {
			CGFloat newMaxX = tgtFrm.origin.x - SPACING;
			if ((anc.h & (AnchorMin | FixedSize)) == AnchorMin)
				frame.size.width = newMaxX - frame.origin.x;
			else frame.origin.x = newMaxX - frame.size.width;
			anc.h |= AnchorMax; if (anc.h & FixedSize) anc.h |= AnchorMin;
		} else if ([attr isEqualToString:@"lower"] && (target.anc.v & AnchorMax)) {
			CGFloat newY = NSMaxY(tgtFrm) + SPACING;
			if ((anc.v & (AnchorMax | FixedSize)) == AnchorMax)
				frame.size.height += frame.origin.y - newY;
			frame.origin.y = newY;
			anc.v |= AnchorMin; if (anc.v & FixedSize) anc.v |= AnchorMax;
		} else if ([attr isEqualToString:@"upper"] && (target.anc.v & AnchorMin)) {
			CGFloat newMaxY = tgtFrm.origin.y - SPACING;
			if ((anc.v & (AnchorMin | FixedSize)) == AnchorMin)
				frame.size.height = newMaxY - frame.origin.y;
			else frame.origin.y = newMaxY - frame.size.height;
			anc.v |= AnchorMax; if (anc.v & FixedSize) anc.v |= AnchorMin;
		} else if ([attr isEqualToString:@"baseline"] &&
			(target.anc.v & (AnchorMin | AnchorMax)) == (AnchorMin | AnchorMax)) {
			frame.origin.y = tgtFrm.origin.y +
				target.baselineOffsetFromBottom - info.baselineOffsetFromBottom;
			anc.v |= AnchorMin | AnchorMax;
		} else continue;
		info.frame = frame;
		info.anc = anc;
		[dependency removeObjectAtIndex:i];
		reduced = YES;
#ifdef DEBUG
		puts([NSString stringWithFormat:@"2ndPass %@ %@",attr,info].UTF8String);
#endif
	}} while (reduced && dependency.count > 0);
	if (dependency.count > 0) {
		NSMutableString *ms =
			[NSMutableString stringWithString:@"Could not solve dependencies for "];
		for (NSDictionary *item in dependency)
			[ms appendFormat:@"%@(%@:%@) ",
				((PlacedInfo *)item[@"subject"]).name,item[@"attr"], item[@"target"]];
		[ms replaceCharactersInRange:(NSRange){ms.length - 1, 1} withString:@"."];
		error_return(ms);
	}
	for (PlacedInfo *plc in infoByName.objectEnumerator)
		[plc placeItInParentView:window.contentView];
	[window center];
	[window makeKeyAndOrderFront:nil];
	NSApplication *app = NSApplication.sharedApplication;
	app.activationPolicy = NSApplicationActivationPolicyRegular;
	[app activateIgnoringOtherApps:YES];
	[app run];
	}
	return 0;
}
