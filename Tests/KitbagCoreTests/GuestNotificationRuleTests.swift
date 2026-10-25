import Testing

@testable import KitbagCore

struct GuestNotificationRuleTests {
  @Test func aHeadwayNotificationWithoutAPictureGetsTheIcon() {
    #expect(
      GuestNotificationRule.shouldAddHeadwayIcon(
        identifier: "headway.reminder.abc", attachmentCount: 0, alreadyBranded: false))
    // The ones posted at once, with no trigger, have this shape (a route running late, a service alert).
    #expect(
      GuestNotificationRule.shouldAddHeadwayIcon(
        identifier: "headway.watch.42", attachmentCount: 0, alreadyBranded: false))
  }

  @Test func aNotificationThatCarriesItsOwnPictureIsLeftAsItIs() {
    // Headway 0.7 puts the route's colour and the minutes late in a picture of its own ("badge"); replacing it with the
    // icon would take away what the notification says.
    #expect(
      !GuestNotificationRule.shouldAddHeadwayIcon(
        identifier: "headway.watch.42", attachmentCount: 1, alreadyBranded: false))
    #expect(
      !GuestNotificationRule.shouldAddHeadwayIcon(
        identifier: "headway.watch.42", attachmentCount: 3, alreadyBranded: false))
  }

  @Test func aBrandedNotificationIsNotBrandedAgain() {
    #expect(
      !GuestNotificationRule.shouldAddHeadwayIcon(
        identifier: "headway.reminder.abc", attachmentCount: 0, alreadyBranded: true))
  }

  @Test func onlyHeadwaysNotificationsAreTouched() {
    for identifier in [
      "kitbag.deadline.1", "kitbag.snooze.2", "kitbag.test.icon", "mantissa.x", "headway", "Headway.reminder.1", "",
    ] {
      #expect(
        !GuestNotificationRule.shouldAddHeadwayIcon(identifier: identifier, attachmentCount: 0, alreadyBranded: false))
    }
  }
}
