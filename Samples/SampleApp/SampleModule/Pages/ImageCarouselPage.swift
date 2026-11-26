import Foundation
import RsUI
import WinUI

/// 图片轮播演示：上段用远程 URL 走滚动 / PipsPager / 失败态，下段用本地文件 URL
/// 演示相邻缩放幅度。
final class ImageCarouselPage: RsUI.Page {
    var view: UIElement?
    let url = URL(string: "rs://\(sampleModuleID)/image-carousel")!
    var title: String { tr("Image Carousel") }

    var header: Any? {
        featurePageHeader(
            title: tr("Image Carousel"),
            description: tr(
                "A vertical image carousel: the slide nearest the viewport center stays full size "
                + "while the others shrink with their distance from it. The scrollbar is hidden; "
                + "a PipsPager beside the viewport indicates the current page."
            ))
    }

    var content: WinUI.UIElement? {
        let sections = [makeRemoteSection(), makeLocalSection()]
        return featurePageContent(sections)
    }

    // MARK: - Remote images

    private func makeRemoteSection() -> UIElement {
        let carousel = ImageCarousel()
        carousel.height = 320
        // 格子宽度会拉伸到宿主给的宽度；这里限宽，否则宽窗口里每张图是一长条底色中间一张小图。
        carousel.width = 480
        carousel.horizontalAlignment = .left
        // 同屏几张取决于图片高与控件高之比：320 高的控件里 120 约露出三张。
        carousel.slideHeight = 120

        let readout = makeCaption("")
        func updateReadout() {
            let count = carousel.imageURLs.count
            readout.text = count == 0
                ? tr("No images")
                : String(
                    format: tr("Selected: %d of %d"), Int32(carousel.selectedIndex + 1), Int32(count))
        }
        carousel.selectedIndexChanged.addHandler { _, _ in updateReadout() }

        func load(_ remoteCount: Int) {
            carousel.setImageURLs(Self.remoteImageURLs(count: remoteCount) + [Self.missingImageURL])
            updateReadout()
        }

        let controls = StackPanel()
        controls.orientation = .horizontal
        controls.spacing = 8
        readout.verticalAlignment = .center
        controls.children.append(readout)
        controls.children.append(makeButton(tr("Previous")) { carousel.selectedIndex -= 1 })
        controls.children.append(makeButton(tr("Next")) { carousel.selectedIndex += 1 })
        controls.children.append(makeButton(tr("Load 12")) { load(11) })
        controls.children.append(makeButton(tr("Load 6")) { load(5) })
        controls.children.append(makeButton(tr("Clear")) {
            carousel.setImageURLs([])
            updateReadout()
        })

        // 实时看"图片高 / 控件高"的比例效果。
        let heightBox = WinUI.NumberBox()
        heightBox.header = tr("Slide height")
        heightBox.minimum = 60
        heightBox.maximum = 300
        heightBox.smallChange = 10
        heightBox.value = carousel.slideHeight
        heightBox.width = 160
        heightBox.spinButtonPlacementMode = .inline
        try? AutomationProperties.setName(heightBox, tr("Slide height"))
        heightBox.valueChanged.addHandler { _, args in
            // 清空输入框时值是 NaN
            if let height = args?.newValue, height.isFinite {
                carousel.slideHeight = height
            }
        }

        let sizing = StackPanel()
        sizing.orientation = .horizontal
        sizing.spacing = 16
        sizing.children.append(heightBox)

        load(11)
        return makeSection(
            title: tr("Remote images"),
            caption: tr(
                "Images load from their URLs (picsum.photos); the last one points to a missing file "
                + "and shows the failure state. Scrolling is native ScrollView behavior: the mouse wheel "
                + "or a touch pan scrolls freely and comes to rest on a page, clicking a slide centers "
                + "it, and the pips jump straight to a page. The spin box changes the slide height live: "
                + "the shorter the slide relative to the control, the more slides share the screen."
            ),
            views: [carousel, controls, sizing])
    }

    // MARK: - Local files

    private func makeLocalSection() -> UIElement {
        let carousel = ImageCarousel()
        carousel.setImageURLs(localImageURLs())
        carousel.height = 320
        carousel.width = 320
        carousel.horizontalAlignment = .left
        carousel.slideHeight = 120

        let scaleLabel = TextBlock()
        scaleLabel.text = tr("Neighbor scale")
        scaleLabel.verticalAlignment = .center

        let scaleSlider = WinUI.Slider()
        // Slider 无可见文字标签（标签是旁边的 TextBlock），为 UIA 提供名称。
        try? AutomationProperties.setName(scaleSlider, tr("Neighbor scale"))
        scaleSlider.minimum = 0.5
        scaleSlider.maximum = 1
        scaleSlider.stepFrequency = 0.05
        scaleSlider.value = carousel.neighborScale
        scaleSlider.width = 180
        let scaleReadout = makeCaption(String(format: "%.2f", carousel.neighborScale))
        scaleReadout.minWidth = 32
        scaleReadout.verticalAlignment = .center
        scaleSlider.valueChanged.addHandler { _, args in
            guard let args else { return }
            carousel.neighborScale = args.newValue
            scaleReadout.text = String(format: "%.2f", args.newValue)
        }

        let controls = StackPanel()
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.children.append(scaleLabel)
        controls.children.append(scaleSlider)
        controls.children.append(scaleReadout)

        return makeSection(
            title: tr("Local files — neighbor scale"),
            caption: tr(
                "The 15 cell icons from the resource bundle as file URLs. "
                + "Drag the slider to change how much the neighboring slides shrink."
            ),
            views: [carousel, controls])
    }

    // MARK: - Factories

    private func makeSection(title: String, caption: String, views: [UIElement]) -> UIElement {
        let section = StackPanel()
        section.spacing = 8
        section.margin = Thickness(left: 0, top: 0, right: 0, bottom: 8)
        section.children.append(makeSectionTitle(title))
        section.children.append(makeCaption(caption))
        for view in views {
            section.children.append(view)
        }
        return section
    }

    private func makeButton(_ title: String, action: @escaping () -> Void) -> Button {
        let button = Button()
        button.content = title
        button.click.addHandler { _, _ in action() }
        return button
    }

    /// picsum 的 seed URL 对同一 seed 返回同一张图。
    private static func remoteImageURLs(count: Int) -> [URL] {
        (1...count).compactMap {
            URL(string: "https://picsum.photos/seed/rsui-\($0)/640/360")
        }
    }

    private static let missingImageURL = URL(
        fileURLWithPath: "C:/Windows/Web/missing-carousel-image.jpg")

    private func localImageURLs() -> [URL] {
        [
            "cell-monocyte", "cell-lymphocyte", "cell-basophil", "cell-eosinophil",
            "cell-neutrophil", "cell-macrophage-resting", "cell-macrophage-activated",
            "cell-t-cell", "cell-b-cell", "cell-b-cell-antibodies", "cell-mast-cell",
            "cell-nk-cell", "cell-dendritic-cell", "cell-erythrocytes", "cell-platelets",
        ].compactMap { name in
            App.context.resourceBundle.path(forResource: name, ofType: "png").map {
                URL(fileURLWithPath: $0)
            }
        }
    }
}
