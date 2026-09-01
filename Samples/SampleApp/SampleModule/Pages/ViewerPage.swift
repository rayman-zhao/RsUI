import Foundation
import RsUI
import UWP
import WinUI

final class ViewerPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) {
        self.context = context
    }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
    }

    var url: URL { URL(string: "rs://sample/viewer")! }
    var title: String { tr("Viewer") }

    var content: WinUI.UIElement {
        let viewer = Viewer()

        let border = Border()
        border.background = WinUI.SolidColorBrush(UWP.Color(a: 0xff, r: 0xff, g: 0x00, b: 0x00))
        let centerText = TextBlock()
        centerText.text = tr("Viewer center content")

        centerText.horizontalAlignment = .center
        centerText.verticalAlignment = .center
        border.child = centerText
        viewer.centerContent = border

        let loaded = (try? XamlReader.load(xamlUI)) as! Grid
        let fsbtn = (try? loaded.findName("FullscreenButton")) as! Button
        fsbtn.click.addHandler { [weak self] _, _ in
            guard let self else { return }
            if self.context.isInFullscreen {
                self.context.exitFullscreen()
            } else {
                self.context.enterFullscreen()
            }
        }
        viewer.topContent = loaded

        let leftText = TextBlock()
        leftText.text = tr("Viewer left pane")
        leftText.horizontalAlignment = .center
        leftText.verticalAlignment = .center
        viewer.leftContent = leftText

        let rightPane = SettingsPanel()
        for i in 0..<8 {
            let card = SettingsCard(header: "Group \(i)")
            card.isClickEnabled = true
            card.click.addHandler { _, _ in
                let l = TextBlock()
                l.verticalAlignment = .center
                l.text = "Group \(i)"
                let t = TextBlock()
                t.text = "Second Group"
                rightPane.navigateTo(label: l, cards: [t])
            }
            let card2 = SettingsCard(header: "Group \(i) Not Clickable")
            rightPane.append(glyph: "\u{F0E3}", label: "Group \(i)", cards: [card, card2])
        }

        viewer.rightContent = rightPane

        let bottomText = TextBlock()
        bottomText.text = tr("Viewer bottom pane")
        bottomText.horizontalAlignment = .center
        bottomText.verticalAlignment = .center
        viewer.bottomContent = bottomText

        return viewer
    }

    private var xamlUI: String {
        """
        <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="Blue">
            <Grid.Resources>
                <ResourceDictionary>
                    <Style x:Key="ViewerChromeAppBarButtonStyle" TargetType="AppBarButton">
                        <Setter Property="Width" Value="48"/>
                        <Setter Property="LabelPosition" Value="Collapsed" />
                    </Style>
                </ResourceDictionary>
            </Grid.Resources>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="TopHost" Grid.Column="0" Text="The Viewer Toolbar" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <AppBarButton x:Name="FullscreenButton" Icon="Fullscreen" Grid.Column="1" Style="{StaticResource ViewerChromeAppBarButtonStyle}">
            </AppBarButton>
        </Grid>
        """
    }
}
