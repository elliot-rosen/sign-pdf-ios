import XCTest
import PDFKit
@testable import SimpleSignPDF

final class PDFCoordinateConverterTests: XCTestCase {

    var testPage: PDFPage!

    override func setUpWithError() throws {
        // Create a test PDF page (US Letter size: 612 x 792 points)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        testPage = PDFPage()
    }

    override func tearDownWithError() throws {
        testPage = nil
    }

    // MARK: - Clamping Tests

    func testClampKeepsAnnotationWithinBounds() {
        // Annotation that would go off the right edge
        let point = CGPoint(x: 600, y: 100)
        let size = CGSize(width: 100, height: 50)

        let clamped = PDFCoordinateConverter.clamp(
            pdfPoint: point,
            size: size,
            on: testPage
        )

        // Should be clamped to fit within page (612 wide)
        XCTAssertLessThanOrEqual(clamped.x + size.width, 612, "Annotation should not exceed right edge")
        XCTAssertGreaterThanOrEqual(clamped.x, 0, "Annotation should not go off left edge")
    }

    func testClampWithOversizedAnnotation() {
        // Annotation larger than page
        let point = CGPoint(x: 100, y: 100)
        let size = CGSize(width: 800, height: 900)

        let clamped = PDFCoordinateConverter.clamp(
            pdfPoint: point,
            size: size,
            on: testPage
        )

        // Should center the oversized annotation
        let expectedX = (612 - 800) / 2
        let expectedY = (792 - 900) / 2

        XCTAssertEqual(clamped.x, expectedX, accuracy: 0.1, "Oversized annotation should be centered horizontally")
        XCTAssertEqual(clamped.y, expectedY, accuracy: 0.1, "Oversized annotation should be centered vertically")
    }

    func testClampWithPadding() {
        let point = CGPoint(x: 5, y: 5)
        let size = CGSize(width: 100, height: 50)
        let padding: CGFloat = 10

        let clamped = PDFCoordinateConverter.clamp(
            pdfPoint: point,
            size: size,
            on: testPage,
            padding: padding
        )

        // Should respect padding
        XCTAssertGreaterThanOrEqual(clamped.x, padding, "Should respect left padding")
        XCTAssertGreaterThanOrEqual(clamped.y, padding, "Should respect bottom padding")
    }

    // MARK: - Resize Tests

    func testAdjustOriginForResizeMaintainsCenter() {
        let currentOrigin = CGPoint(x: 100, y: 200)
        let currentSize = CGSize(width: 150, height: 75)
        let newSize = CGSize(width: 300, height: 150) // 2x scale

        let currentCenter = CGPoint(
            x: currentOrigin.x + currentSize.width / 2,
            y: currentOrigin.y + currentSize.height / 2
        )

        let newOrigin = PDFCoordinateConverter.adjustOriginForResize(
            currentOrigin: currentOrigin,
            currentSize: currentSize,
            newSize: newSize,
            on: testPage
        )

        let newCenter = CGPoint(
            x: newOrigin.x + newSize.width / 2,
            y: newOrigin.y + newSize.height / 2
        )

        // Center should remain the same (or clamped if needed)
        XCTAssertEqual(currentCenter.x, newCenter.x, accuracy: 1.0, "Center X should be maintained")
        XCTAssertEqual(currentCenter.y, newCenter.y, accuracy: 1.0, "Center Y should be maintained")
    }

    func testCornerResizeKeepsOppositeCornerFixed() {
        let currentOrigin = CGPoint(x: 100, y: 200)
        let currentSize = CGSize(width: 150, height: 75)
        let newSize = CGSize(width: 300, height: 150) // 2x scale

        // Resize from bottom-left, so top-right should stay fixed
        let topRightBefore = CGPoint(
            x: currentOrigin.x + currentSize.width,
            y: currentOrigin.y + currentSize.height
        )

        let newOrigin = PDFCoordinateConverter.adjustOriginForCornerResize(
            currentOrigin: currentOrigin,
            currentSize: currentSize,
            newSize: newSize,
            anchorCorner: .topRight, // top-right stays fixed
            on: testPage
        )

        let topRightAfter = CGPoint(
            x: newOrigin.x + newSize.width,
            y: newOrigin.y + newSize.height
        )

        XCTAssertEqual(topRightBefore.x, topRightAfter.x, accuracy: 1.0, "Top-right X should stay fixed")
        XCTAssertEqual(topRightBefore.y, topRightAfter.y, accuracy: 1.0, "Top-right Y should stay fixed")
    }

    // MARK: - Validation Tests

    func testCenteredPosition() {
        let size = CGSize(width: 100, height: 50)

        let centered = PDFCoordinateConverter.centeredPosition(
            for: size,
            on: testPage
        )

        let expectedX = (612 - 100) / 2
        let expectedY = (792 - 50) / 2

        XCTAssertEqual(centered.x, expectedX, accuracy: 0.1, "Should center horizontally")
        XCTAssertEqual(centered.y, expectedY, accuracy: 0.1, "Should center vertically")
    }

    func testIsWithinBounds() {
        // Point within bounds
        let validPoint = CGPoint(x: 100, y: 100)
        XCTAssertTrue(
            PDFCoordinateConverter.isWithinBounds(pdfPoint: validPoint, on: testPage),
            "Point within bounds should return true"
        )

        // Point outside bounds
        let invalidPoint = CGPoint(x: -10, y: 100)
        XCTAssertFalse(
            PDFCoordinateConverter.isWithinBounds(pdfPoint: invalidPoint, on: testPage),
            "Point outside bounds should return false"
        )
    }

    func testIsValidSize() {
        // Valid size
        let validSize = CGSize(width: 300, height: 200)
        XCTAssertTrue(
            PDFCoordinateConverter.isValidSize(validSize, for: testPage),
            "Reasonable size should be valid"
        )

        // Zero size
        let zeroSize = CGSize(width: 0, height: 50)
        XCTAssertFalse(
            PDFCoordinateConverter.isValidSize(zeroSize, for: testPage),
            "Zero-width size should be invalid"
        )

        // Oversized (> 90% of page)
        let oversized = CGSize(width: 700, height: 900)
        XCTAssertFalse(
            PDFCoordinateConverter.isValidSize(oversized, for: testPage),
            "Oversized annotation should be invalid"
        )
    }

    // MARK: - AnnotationCorner Tests

    func testAnnotationCornerOpposite() {
        XCTAssertEqual(AnnotationCorner.topLeft.opposite, .bottomRight)
        XCTAssertEqual(AnnotationCorner.topRight.opposite, .bottomLeft)
        XCTAssertEqual(AnnotationCorner.bottomLeft.opposite, .topRight)
        XCTAssertEqual(AnnotationCorner.bottomRight.opposite, .topLeft)
    }

    // MARK: - CGRect Extension Tests

    func testRectCenter() {
        let rect = CGRect(x: 100, y: 200, width: 150, height: 75)
        let center = rect.center

        XCTAssertEqual(center.x, 175, accuracy: 0.1)
        XCTAssertEqual(center.y, 237.5, accuracy: 0.1)
    }

    func testRectFromCenter() {
        let center = CGPoint(x: 175, y: 237.5)
        let size = CGSize(width: 150, height: 75)
        let rect = CGRect(center: center, size: size)

        XCTAssertEqual(rect.origin.x, 100, accuracy: 0.1)
        XCTAssertEqual(rect.origin.y, 200, accuracy: 0.1)
        XCTAssertEqual(rect.size.width, 150, accuracy: 0.1)
        XCTAssertEqual(rect.size.height, 75, accuracy: 0.1)
    }
}
