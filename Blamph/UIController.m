//
//  UIController.m
//  Blamph
//
//  Created by Chad Gibbons on 11/15/12.
//  Copyright (c) 2012 Nuclear Bunny Studios, LLC. All rights reserved.
//

#import "UIController.h"
#import "ClientCommand.h"
#import "DateTimeUtils.h"
#import "BeepPacket.h"
#import "CommandPacket.h"
#import "CommandOutputPacket.h"
#import "ErrorPacket.h"
#import "ExitPacket.h"
#import "LoginPacket.h"
#import "PersonalPacket.h"
#import "PingPacket.h"
#import "PongPacket.h"
#import "ProtocolPacket.h"
#import "OpenPacket.h"
#import "StatusPacket.h"

@implementation UIController

@synthesize progressIndicator;
@synthesize inputTextView;
@synthesize outputTextView;
@synthesize connectMenuItem;
@synthesize disconnectMenuItem;
@synthesize menuItemCopy;
@synthesize menuItemPaste;
@synthesize menuItemToggleStatusBar;
@synthesize splitView;
@synthesize bottomConstraint;
@synthesize statusBarView;
@synthesize connectionStatusLabel;
@synthesize connectionTimeLabel;
@synthesize idleTimeLabel;
@synthesize timer;

#define kOutputScrollbackSize   1000

- (id)init
{
    if (self = [super init])
    {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(clientNotify:)
                                                     name:nil
                                                   object:self.client];
    }
    return self;
}

- (void)awakeFromNib
{
    backgroundColor = [NSColor whiteColor];
    openTextColor = [NSColor blackColor];
    openNickColor = [NSColor blueColor];
    personalTextColor = [NSColor darkGrayColor];
    personalNickColor = [NSColor lightGrayColor];
    commandTextColor = [NSColor blackColor];
    errorTextColor = [NSColor redColor];
    statusHeaderColor = [NSColor orangeColor];
    statusTextColor = [NSColor blackColor];
    timestampColor = [NSColor lightGrayColor];
    
    outputFont = [NSFont fontWithName:@"Monaco" size:12.0f];
    timestampFont = [NSFont fontWithName:@"Monaco" size:10.0f];
    
//    [self.outputTextView.layoutManager setDelegate:self];
//
    [self.outputTextView setFont:outputFont];
    [self.outputTextView setBackgroundColor:backgroundColor];
    [self.outputTextView setTextColor:commandTextColor];
    
    [self.window makeFirstResponder:self.inputTextView];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    BOOL valid = YES;
    if (menuItem == self.connectMenuItem)
    {
        valid = ![self.client isConnected];
    }
    else if (menuItem == self.disconnectMenuItem)
    {
        valid = [self.client isConnected];
    }
    return valid;
}

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
    if (aTextView != self.inputTextView)
        return NO;
    
    if (aSelector == @selector(insertNewline:))
    {
        NSString *text = [[aTextView textStorage] string];
        [self submitTextInput:text];
        [aTextView selectAll:nil];
        [aTextView delete:nil];
        return YES;
    }
    
    if (aSelector == @selector(insertTab:))
    {
        NSString *nickname = [self.client.nicknameHistory next];
        if (nickname != nil)
        {
            [self setNickname:nickname];
        }
        else
        {
            NSBeep();
        }
        return YES;
    }
    
    return NO;
}

- (void)submitTextInput:(NSString *)cmd
{
    if (cmd == nil || [cmd length] == 0)
        return;
    
    // if the input isn't prefixed with the command character just send
    // the text as an open message
    if ([cmd characterAtIndex:0] != '/')
    {
        [self.client sendOpenMessage:cmd];
    }
    
    // check if they escaped the / with another and send it as an open
    // message
    else if ([cmd characterAtIndex:1] == '/')
    {
        [self.client sendOpenMessage:[cmd substringFromIndex:1]];
    }
    
    // otherwise, we've got command! see if a ClientCommand has been
    // defined and process it that way, otherwise send a personal message
    // to the Server for any other processing
    else
    {
        cmd = [cmd substringFromIndex:1];
        ClientCommand *command = [ClientCommand commandWithString:cmd];
        if (!command)
        {
            [self.client sendPersonalMessage:@"server"
                                withMsg:cmd];
        }
        else
        {
            [command processCommandWithClient:self.client];
        }
    }
    
    lastMessageSentAt = [NSDate date];
}

- (void)displayText:(NSString *)text
     withForeground:(NSColor *)foreground
      andBackground:(NSColor *)background
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:text];
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, [text length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:background
               range:NSMakeRange(0, [text length])];
    [as addAttribute:NSForegroundColorAttributeName
               value:foreground
               range:NSMakeRange(0, [text length])];
    
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?s)((?:\\w+://|\\bwww\\.[^.])\\S+)"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    
    NSArray *matches = [regex matchesInString:text
                                      options:0
                                        range:NSMakeRange(0, [text length])];
    
    for (NSTextCheckingResult *match in matches)
    {
        NSRange urlRange = [match rangeAtIndex:1];
        NSString *urlText = [text substringWithRange:urlRange];
        
        [as addAttribute:NSLinkAttributeName
                   value:[NSURL URLWithString:urlText]
                   range:urlRange];
    }
    
    [textStorage appendAttributedString:as];
}

- (void)setNickname:(NSString *)nickname
{
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\S*)\\s*(\\S*)(.*)"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    NSTextStorage *storage = [self.inputTextView textStorage];
    [storage beginEditing];
    
    NSString *inputText = [storage string];
    NSString *newText;
    
    if ([inputText length] > 0 && [inputText characterAtIndex:0] == '/')
    {
        NSArray *matches = [regex matchesInString:inputText
                                          options:0
                                            range:NSMakeRange(1, [inputText length] - 1)];
        if ([matches count] > 0)
        {
            NSTextCheckingResult *match = [matches objectAtIndex:0];
            NSRange commandRange = [match rangeAtIndex:1];
            NSRange argsRange = [match rangeAtIndex:3];
            NSString *command = [inputText substringWithRange:commandRange];
            NSString *args = [[inputText substringWithRange:argsRange]
                              stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            newText = [NSString stringWithFormat:@"/%@ %@ %@", command, nickname, args];
        }
    }
    else
    {
        newText = [NSString stringWithFormat:@"/m %@ %@", nickname, inputText];
    }
    
    [self.inputTextView selectAll:nil];
    [self.inputTextView setString:newText];
    [storage endEditing];
    
    NSRange range = NSMakeRange(storage.length - 1, 1);
    [self.inputTextView scrollRangeToVisible:range];
    [self.window makeFirstResponder:self.inputTextView];
}

- (BOOL)textView:(NSTextView *)aTextView
   clickedOnLink:(id)link
         atIndex:(NSUInteger)charIndex
{
    DLog(@"textView clickedOnLink: %@", link);
    if (aTextView != self.outputTextView)
        return NO;
    
    BOOL handled = NO;
    if ([link isKindOfClass:[NSURL class]])
    {
        [[NSWorkspace sharedWorkspace] openURL:link];
        handled = YES;
    }
    else if ([link isKindOfClass:[NSString class]])
    {
        NSString *nickname = link;
        [self setNickname:nickname];
        handled = YES;
    }
    return handled;
}

- (IBAction)selectAll:(id)sender
{
    [self.inputTextView selectAll:sender];
}

- (IBAction)copy:(id)sender
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    (void)[pasteboard clearContents];
    NSArray *selectedRanges = [self.outputTextView selectedRanges];
    NSMutableArray *selectedText = [NSMutableArray arrayWithCapacity:[selectedRanges count]];
    for (NSValue *rangeValue in selectedRanges)
    {
        NSRange r = [rangeValue rangeValue];
        [selectedText addObject:[[self.outputTextView textStorage] attributedSubstringFromRange:r]];
    }
    
    (void)[pasteboard writeObjects:selectedText];
}

- (IBAction)paste:(id)sender
{
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSArray *classes = [[NSArray alloc] initWithObjects:[NSString class], nil];
    NSDictionary *options = [NSDictionary dictionary];
    NSArray *copiedItems = [pasteboard readObjectsForClasses:classes
                                                     options:options];
    if (copiedItems != nil)
    {
        [self.inputTextView pasteAsPlainText:copiedItems];
        [self.window makeFirstResponder:self.inputTextView];
    }
}

- (IBAction)toggleStatusBar:(id)sender
{
    BOOL isHidden = [self.statusBarView isHidden];
    [self.statusBarView setHidden:!isHidden];
    
    NSDictionary *views = nil;
    NSArray *constraints = nil;
    if (isHidden)
    {
        views = [NSDictionary dictionaryWithObjectsAndKeys:
                 self.splitView, @"splitview",
                 self.statusBarView, @"bottomview",
                 nil];
        constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[splitview]-(0)-[bottomview]"
                                                              options:0
                                                              metrics:nil
                                                                views:views];
    }
    else
    {
        // the status bar was previously visible, so change our bottom
        // constraint to be relative to the superview, not the status bar
        views = [NSDictionary dictionaryWithObjectsAndKeys:self.splitView, @"splitview",
                 nil];
        constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[splitview]-(0)-|"
                                                              options:0
                                                              metrics:nil
                                                                views:views];
    }
    
    [self.splitView.superview removeConstraints:[NSArray arrayWithObject:self.bottomConstraint]];
    self.bottomConstraint = constraints[0];
    [self.splitView.superview  addConstraints:constraints];
    [self.splitView.superview setNeedsUpdateConstraints:YES];
}

- (void)displayMessageTimestamp
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    
    CFDateRef date = CFDateCreate(kCFAllocatorDefault, now);
    
    CFLocaleRef currentLocale = CFLocaleCopyCurrent();
    
    CFDateFormatterRef dateFormatter = CFDateFormatterCreate(NULL,
                                                             currentLocale,
                                                             kCFDateFormatterNoStyle,
                                                             kCFDateFormatterShortStyle);
    
    CFStringRef formattedString = CFDateFormatterCreateStringWithDate(NULL,
                                                                      dateFormatter,
                                                                      date);
    
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = [NSString stringWithFormat:@"%@ ", formattedString];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc]
                                     initWithString:s];
    [as addAttribute:NSFontAttributeName
               value:timestampFont
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSForegroundColorAttributeName
               value:timestampColor
               range:NSMakeRange(0, [as length])];
    
    [textStorage appendAttributedString:as];

    CFRelease(date);
    CFRelease(currentLocale);
    CFRelease(dateFormatter);
    CFRelease(formattedString);
}

- (void)displayOpenPacket:(OpenPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = [NSString stringWithFormat:@"<%@>", p.nick];
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:s];
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, [p.nick length] + 2)];
    [as addAttribute:NSLinkAttributeName value:p.nick
               range:NSMakeRange(1, [p.nick length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, [p.nick length] + 2)];
    [as addAttribute:NSForegroundColorAttributeName
               value:openNickColor
               range:NSMakeRange(0, [p.nick length] + 2)];
    
    [textStorage appendAttributedString:as];
    
    [self displayText:[NSString stringWithFormat:@" %@\n", p.text]
       withForeground:openTextColor
        andBackground:backgroundColor];
}

- (void)displayPersonalPacket:(PersonalPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = [NSString stringWithFormat:@"<*%@*>", p.nick];
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:s];
    [as addAttribute:NSLinkAttributeName
               value:p.nick
               range:NSMakeRange(2, [p.nick length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, [p.nick length] + 4)];
    [as addAttribute:NSForegroundColorAttributeName
               value:personalNickColor
               range:NSMakeRange(0, [p.nick length] + 4)];
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, [p.nick length] + 4)];
    [textStorage appendAttributedString:as];
    
    [self displayText:[NSString stringWithFormat:@" %@\n", p.text]
       withForeground:personalTextColor
        andBackground:backgroundColor];
}

- (void)displayBeepPacket:(BeepPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = [NSString stringWithFormat:@"[=Beep!=] %@ has sent you a beep\n", p.nick];
    const NSUInteger headerLength = 10; // [=Beep=]<space> == 10
    const NSUInteger textLength = [s length];
    const NSUInteger nickLength = [p.nick length];
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:s];
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, textLength)];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, textLength)];
    [as addAttribute:NSForegroundColorAttributeName
               value:statusHeaderColor
               range:NSMakeRange(0, headerLength)];
    [as addAttribute:NSLinkAttributeName
               value:p.nick
               range:NSMakeRange(headerLength, nickLength)];
    [as addAttribute:NSForegroundColorAttributeName
               value:statusTextColor
               range:NSMakeRange(headerLength + nickLength, textLength - nickLength - headerLength)];
    
    [textStorage appendAttributedString:as];
    
    NSBeep();
}

- (void)displayExitPacket:(ExitPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc]
                                     initWithString:@"[=Disconnected=]\n"];
    
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSForegroundColorAttributeName
               value:statusHeaderColor
               range:NSMakeRange(0, [as length])];
    
    [textStorage appendAttributedString:as];
}

- (void)displayPingPacket:(PingPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc]
                                     initWithString:@"[=Ping!=]\n"];
    
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSForegroundColorAttributeName
               value:statusHeaderColor
               range:NSMakeRange(0, [as length])];
    
    [textStorage appendAttributedString:as];
}

- (void)displayProtocolPacket:(ProtocolPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = [NSString stringWithFormat:@"Connected to the %@ server (%@)\n",
                   p.serverName, p.serverDescription];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:s];
    
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSForegroundColorAttributeName
               value:commandTextColor
               range:NSMakeRange(0, [as length])];
    
    [textStorage appendAttributedString:as];
}

- (void)displayStatusPacket:(StatusPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = [NSString stringWithFormat:@"[=%@=] %@\n", p.header, p.text];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:s];
    NSUInteger textLength = [as length];
    NSUInteger headerLength = 4 + [p.header length];
    
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, [as length])];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, textLength)];
    [as addAttribute:NSForegroundColorAttributeName
               value:statusHeaderColor
               range:NSMakeRange(0, headerLength)];
    [as addAttribute:NSForegroundColorAttributeName
               value:statusTextColor
               range:NSMakeRange(headerLength + 1, textLength - headerLength - 1)];
    
    
    [textStorage appendAttributedString:as];
}

- (void)displayErrorPacket:(ErrorPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = [NSString stringWithFormat:@"[=Error=] %@\n", p.errorText];
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:s];
    NSUInteger textLength = [as length];
    NSUInteger headerLength = 9; // [=Error=]
    
    [as addAttribute:NSFontAttributeName
               value:outputFont
               range:NSMakeRange(0, textLength)];
    [as addAttribute:NSBackgroundColorAttributeName
               value:backgroundColor
               range:NSMakeRange(0, textLength)];
    [as addAttribute:NSForegroundColorAttributeName
               value:errorTextColor
               range:NSMakeRange(0, headerLength)];
    [as addAttribute:NSForegroundColorAttributeName
               value:errorTextColor
               range:NSMakeRange(headerLength + 1, textLength - headerLength - 1)];
    
    [textStorage appendAttributedString:as];
}

- (void)displayCommandOutputPacket:(CommandOutputPacket *)p
{
    const NSTextStorage *textStorage = self.outputTextView.textStorage;
    
    NSString *s = nil;
    NSMutableAttributedString *as = nil;
    
    if ([p.outputType compare:@"gh"] == NSOrderedSame)
    {
        as = [[NSMutableAttributedString alloc] initWithString:@"Group     ## S  Moderator    \n"];
        [as addAttribute:NSFontAttributeName
                   value:outputFont
                   range:NSMakeRange(0, [as length])];
        [as addAttribute:NSBackgroundColorAttributeName
                   value:backgroundColor
                   range:NSMakeRange(0, [as length])];
        [as addAttribute:NSForegroundColorAttributeName
                   value:commandTextColor
                   range:NSMakeRange(0, [as length])];
        [textStorage appendAttributedString:as];
    }
    else if ([p.outputType compare:@"wh"] == NSOrderedSame)
    {
        as = [[NSMutableAttributedString alloc] initWithString:@"   Nickname      Idle      Sign-on  Account\n"];
        [as addAttribute:NSFontAttributeName
                   value:outputFont
                   range:NSMakeRange(0, [as length])];
        [as addAttribute:NSBackgroundColorAttributeName
                   value:backgroundColor
                   range:NSMakeRange(0, [as length])];
        [as addAttribute:NSForegroundColorAttributeName
                   value:commandTextColor
                   range:NSMakeRange(0, [as length])];
        [textStorage appendAttributedString:as];
    }
    else if ([p.outputType compare:@"wl"] == NSOrderedSame)
    {
        NSMutableString *ms = [NSMutableString stringWithCapacity:80];
        [ms appendFormat:@"%c", [p isModerator] ? '*' : ' '];
        
        NSString *nickname = [p nickname];
        [ms appendFormat:@"%@", nickname];
        NSUInteger pad = 12 - [nickname length];
        if (pad > 0)
        {
            [ms appendString:[@"" stringByPaddingToLength:pad
                                               withString:@" "
                                          startingAtIndex:0]];
        }
        
        [ms appendFormat:@" %@ ", [self formatElapsedTime:[p idleTime]]];
        [ms appendFormat:@"%@ ", [self formatEventTime:[p signOnTime]]];
        [ms appendFormat:@"%@@%@\n", p.username, p.hostname];
        s = ms;
        
        NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:s];
        [as addAttribute:NSFontAttributeName
                   value:outputFont
                   range:NSMakeRange(0, [as length])];
        [as addAttribute:NSBackgroundColorAttributeName
                   value:backgroundColor
                   range:NSMakeRange(0, [as length])];
        [as addAttribute:NSForegroundColorAttributeName
                   value:commandTextColor
                   range:NSMakeRange(0, [as length])];
        [as addAttribute:NSForegroundColorAttributeName
                   value:openNickColor
                   range:NSMakeRange(1, [[p nickname] length])];
        [as addAttribute:NSLinkAttributeName
                   value:[p nickname]
                   range:NSMakeRange(1, [[p nickname] length])];
        [textStorage appendAttributedString:as];
    }
    else
    {
        [self displayText:[NSString stringWithFormat:@"%@\n", p.output]
           withForeground:commandTextColor
            andBackground:backgroundColor];
    }
}

- (NSString *)formatElapsedTime:(NSTimeInterval)elapsedTime
{
    return [DateTimeUtils formatElapsedTime:elapsedTime];
}

- (NSString *)formatEventTime:(NSDate *)time
{
    return [DateTimeUtils formatEventTime:time];
}

- (void)fireTimer:(id)arg
{
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    NSTimeInterval start = [connectedTime timeIntervalSince1970];
    NSTimeInterval elapsedTime = now - start;
    NSString *elapsedText = [DateTimeUtils formatSimpleTime:elapsedTime];
    [connectionTimeLabel setStringValue:[NSString stringWithFormat:@"Connected: %@", elapsedText]];
    
    start = [lastMessageSentAt timeIntervalSince1970];
    NSTimeInterval idleTime = now - start;
    NSString *idleText = [DateTimeUtils formatSimpleTime:idleTime];
    [idleTimeLabel setStringValue:[NSString stringWithFormat:@"Idle: %@", idleText]];
}

- (void)handlePacket:(const ICBPacket *)packet
{
    NSTextStorage *textStorage = [self.outputTextView textStorage];
    
    [textStorage beginEditing];
    
    [self displayMessageTimestamp];
    
    if ([packet isKindOfClass:[OpenPacket class]])
    {
        [self displayOpenPacket:(OpenPacket *)packet];
    }
    else if ([packet isKindOfClass:[PersonalPacket class]])
    {
        [self displayPersonalPacket:(PersonalPacket *)packet];
    }
    else if ([packet isKindOfClass:[CommandOutputPacket class]])
    {
        [self displayCommandOutputPacket:(CommandOutputPacket *)packet];
    }
    else if ([packet isKindOfClass:[BeepPacket class]])
    {
        [self displayBeepPacket:(BeepPacket *)packet];
    }
    else if ([packet isKindOfClass:[ExitPacket class]])
    {
        [self displayExitPacket:(ExitPacket *)packet];
    }
    else if ([packet isKindOfClass:[PingPacket class]])
    {
        [self displayPingPacket:(PingPacket *)packet];
    }
    else if ([packet isKindOfClass:[ProtocolPacket class]])
    {
        [self displayProtocolPacket:(ProtocolPacket *)packet];
    }
    else if ([packet isKindOfClass:[ErrorPacket class]])
    {
        [self displayErrorPacket:(ErrorPacket *)packet];
    }
    else if ([packet isKindOfClass:[StatusPacket class]])
    {
        [self displayStatusPacket:(StatusPacket *)packet];
    }
    else if ([packet isKindOfClass:[LoginPacket class]])
    {
        [[self.outputTextView.textStorage mutableString] appendString:@"\n"];
    }
    
    NSArray *paragraphs = [textStorage paragraphs];
    NSUInteger n = [paragraphs count];
    if (n >= kOutputScrollbackSize)
    {
        NSUInteger len = 0;
        for (NSUInteger i  = 0; i < n - kOutputScrollbackSize; i++)
        {
            len += [[paragraphs objectAtIndex:i] length];
        }
        NSRange r = NSMakeRange(1, len);
        [textStorage deleteCharactersInRange:r];
    }
    
    [textStorage endEditing];
    [self scrollToEnd];
}

- (void)scrollToEnd
{
    NSView *superview = [self.outputTextView superview];
    if (![superview isKindOfClass:[NSClipView class]])
        return;
    else
    {
        NSClipView *clipView = (NSClipView *)superview;
        [clipView scrollToPoint:[clipView constrainScrollPoint:NSMakePoint(0,[self.outputTextView
                                                                              frame].size.height)]];
        [[clipView superview] reflectScrolledClipView:clipView];
    }    
}

- (void)clientNotify:(NSNotification *)notification
{
    if ([[notification name] compare:kICBClient_packet] == NSOrderedSame)
    {
        const ICBPacket *packet = [notification object];
        [self handlePacket:packet];
    }
    else if ([[notification name] compare:kICBClient_connecting] == NSOrderedSame)
    {
        [connectionStatusLabel setStringValue:@"Connecting"];

        [progressIndicator setHidden:NO];
        [progressIndicator startAnimation:self];
    }
    else if ([[notification name] compare:kICBClient_connectfailed] == NSOrderedSame)
    {
        [connectionStatusLabel setStringValue:@"Connect Failed"];
        [progressIndicator stopAnimation:self];
        [progressIndicator setHidden:YES];
    }
    else if ([[notification name] compare:kICBClient_connected] == NSOrderedSame)
    {
        [connectionStatusLabel setStringValue:@"Connected"];

        [progressIndicator stopAnimation:self];
        [progressIndicator setHidden:YES];
        
        [self.idleTimeLabel setHidden:NO];
        [self.connectionTimeLabel setHidden:NO];
        
        connectedTime = [NSDate date];
        lastMessageSentAt = [NSDate date];
        
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                      target:self
                                                    selector:@selector(fireTimer:)
                                                    userInfo:nil
                                                     repeats:YES];
    }
    else if ([[notification name] compare:kICBClient_disconnecting] == NSOrderedSame)
    {
        [connectionStatusLabel setStringValue:@"Disconnected"];
    }
    else if ([[notification name] compare:kICBClient_disconnected] == NSOrderedSame)
    {
        [connectionStatusLabel setStringValue:@"Disconnected"];
        
        [self.timer invalidate];
        self.timer = nil;
        [self.idleTimeLabel setHidden:YES];
        [self.connectionTimeLabel setHidden:YES];
    }
    else if ([[notification name] compare:kICBClient_loginOK] == NSOrderedSame)
    {
    }
}

#pragma mark -

- (void)layoutManager:(NSLayoutManager *)layoutManager
didCompleteLayoutForTextContainer:(NSTextContainer *)textContainer
                atEnd:(BOOL)layoutFinishedFlag
{
//    DLog(@"didCompletelLayoutForTextContainer layoutfinished=%d", layoutFinishedFlag);
}

@end
