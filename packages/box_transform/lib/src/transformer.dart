import 'dart:developer';
import 'dart:math' hide log;

import 'package:vector_math/vector_math.dart';

import '../box_transform.dart';
import 'resizers/resizer.dart';

/// A class that transforms a [Box] in several different supported forms.
class BoxTransformer {
  /// A private constructor to prevent instantiation.
  const BoxTransformer._();

  /// Rotates the given [initialRect] with the given [initialLocalPosition] of
  /// the mouse cursor and wherever [localPosition] of the mouse cursor is
  /// currently at.
  ///
  /// The [clampingRect] is the rect that the [initialRect] is not allowed
  /// to go outside of when dragging or resizing.
  static RawRotateResult rotate({
    required Box initialRect,
    required Vector2 initialLocalPosition,
    required Vector2 localPosition,
    required double initialRotation,
    Box clampingRect = Box.largest,
    BindingStrategy bindingStrategy = BindingStrategy.boundingBox,
  }) {
    final Vector2 delta = localPosition - initialLocalPosition;
    final Vector2 from = initialRect.center - initialLocalPosition;
    final Vector2 to = initialRect.center - localPosition;
    double rotation = atan2(
      from.x * to.y - from.y * to.x,
      from.x * to.x + from.y * to.y,
    ) + initialRotation;

    // Convert from 0->180->-180->0 to 0->360.
    // if (rotation < 0) {
    //   rotation += 2 * pi;
    // }

    print('rotation: ${rotation * 180 / pi}');

    final initialBoundingRect = calculateBoundingRect(
      rotation: rotation,
      unrotatedBox: initialRect,
    );

    return RotateResult(
      rect: initialRect,
      boundingRect: initialBoundingRect,
      oldBoundingRect: initialBoundingRect,
      delta: delta,
      rawSize: initialRect.size,
      rotation: rotation,
    );
  }

  /// Calculates the new position of the [initialRect] based on the
  /// [initialLocalPosition] of the mouse cursor and wherever [localPosition]
  /// of the mouse cursor is currently at.
  ///
  /// The [clampingRect] is the rect that the [initialRect] is not allowed
  /// to go outside of when dragging or resizing.
  static RawMoveResult move({
    required Box initialRect,
    required Vector2 initialLocalPosition,
    required Vector2 localPosition,
    double rotation = 0.0,
    Box clampingRect = Box.largest,
    BindingStrategy bindingStrategy = BindingStrategy.boundingBox,
  }) {
    final Vector2 delta = localPosition - initialLocalPosition;
    final initialBoundingRect = calculateBoundingRect(
      rotation: rotation,
      unrotatedBox: initialRect,
    );

    // If the box is rotated, the incoming delta is also rotated. We need to
    // unrotate the delta to get the actual delta.
    if (rotation != 0) {
      Matrix2.rotation(rotation).transform(delta);
    }

    final Vector2 clampedDelta;
    switch (bindingStrategy) {
      case BindingStrategy.originalBox:
        final Box unclampedRect = initialRect.translate(delta.x, delta.y);
        final Box clampedRect = clampingRect.containOther(unclampedRect);
        clampedDelta = clampedRect.topLeft - initialRect.topLeft;
        break;
      case BindingStrategy.boundingBox:
        final Box unclampedRect =
            initialBoundingRect.translate(delta.x, delta.y);
        final Box clampedRect = clampingRect.containOther(unclampedRect);
        clampedDelta = clampedRect.topLeft - initialBoundingRect.topLeft;
        break;
    }

    final Box newRect = initialRect.translate(clampedDelta.x, clampedDelta.y);
    final Box newBoundingRect =
        initialBoundingRect.translate(clampedDelta.x, clampedDelta.y);

    return MoveResult(
      rect: newRect,
      oldRect: initialRect,
      boundingRect: newBoundingRect,
      oldBoundingRect: initialBoundingRect,
      delta: delta,
      rawSize: newRect.size,
      largestRect: clampingRect,
    );
  }

  /// Resizes the given [initialRect] with given [initialLocalPosition] of
  /// the mouse cursor and wherever [localPosition] of the mouse cursor is
  /// currently at.
  ///
  /// Specifying the [handle] and [resizeMode] will determine how the
  /// [initialRect] will be resized.
  ///
  /// The [initialFlip] helps determine the initial state of the rectangle.
  ///
  /// The [clampingRect] is the rect that the [initialRect] is not allowed
  /// to go outside of when dragging or resizing.
  ///
  /// The [constraints] is the constraints that the [initialRect] is not allowed
  /// to shrink or grow beyond.
  ///
  /// [allowResizeOverflow] decides whether to allow the rect to overflow the
  /// resize operation to its opposite side to continue the resize operation
  /// until its constrained on both sides.
  ///
  /// If this is set to false, the rect will cease the resize operation the
  /// instant it hits an edge of the [clampingRect].
  ///
  /// If this is set to true, the rect will continue the resize operation until
  /// it is constrained to both sides of the [clampingRect].
  static RawResizeResult resize({
    required Box initialRect,
    required Vector2 initialLocalPosition,
    required Vector2 localPosition,
    required HandlePosition handle,
    required ResizeMode resizeMode,
    required Flip initialFlip,
    double rotation = 0.0,
    Box clampingRect = Box.largest,
    Constraints constraints = const Constraints.unconstrained(),
    bool allowFlipping = true,
    BindingStrategy bindingStrategy = BindingStrategy.boundingBox,
  }) {
    if (handle == HandlePosition.none) {
      log('Using bottomRight handle instead of none.');
      handle = HandlePosition.bottomRight;
    }

    final initialBoundingRect = calculateBoundingRect(
      rotation: rotation,
      unrotatedBox: initialRect,
    );

    Vector2 delta = localPosition - initialLocalPosition;

    // getFlipForRect uses delta instead of localPosition to know exactly when
    // to flip based on the current local position of the mouse cursor.
    final Flip currentFlip = !allowFlipping
        ? Flip.none
        : getFlipForRect(initialRect, delta, handle, resizeMode);

    // This sets the constraints such that it reflects flipRect state.
    if (allowFlipping &&
        (constraints.minWidth == 0 || constraints.minHeight == 0)) {
      // Rect flipping is enabled, but minWidth or minHeight is 0 which
      // means it won't be able to flip. So we update the constraints
      // to allow flipping.
      constraints = Constraints(
        minWidth: constraints.minWidth == 0
            ? -constraints.maxWidth
            : constraints.minWidth,
        minHeight: constraints.minHeight == 0
            ? -constraints.maxHeight
            : constraints.minHeight,
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      );
    } else if (!allowFlipping && constraints.isUnconstrained) {
      // Rect flipping is disabled, but the constraints are unconstrained.
      // So we update the constraints to prevent flipping.
      constraints = Constraints(
        minWidth: 0,
        minHeight: 0,
        maxWidth: constraints.maxWidth,
        maxHeight: constraints.maxHeight,
      );
    }

    final Box bindingRect = switch (bindingStrategy) {
      BindingStrategy.originalBox => initialRect,
      BindingStrategy.boundingBox => initialBoundingRect,
    };
    final double bindingWidth = bindingRect.width;
    final double bindingHeight = bindingRect.height;

    // Check if clampingRect is smaller than initialRect.
    // If it is, then we return the initialRect and not resize it.
    if (clampingRect.width < bindingWidth ||
        clampingRect.height < bindingHeight) {
      return ResizeResult(
        rect: initialRect,
        oldRect: initialRect,
        boundingRect: initialBoundingRect,
        oldBoundingRect: initialBoundingRect,
        flip: initialFlip,
        resizeMode: resizeMode,
        delta: delta,
        handle: handle,
        rawSize: initialRect.size,
        largestRect: clampingRect,
        minWidthReached: false,
        minHeightReached: false,
        maxHeightReached: false,
        maxWidthReached: false,
      );
    }

    // Symmetric resizing requires the delta to be doubled since it grows or
    // shrinks in all directions from center.
    if (resizeMode.hasSymmetry) delta = Vector2(delta.x * 2, delta.y * 2);

    // No constraints or clamping is done. Only delta is applied to the
    // initial rect.
    final Box explodedRect = _applyDelta(
      initialRect: initialRect,
      handle: handle,
      delta: delta,
      resizeMode: resizeMode,
      allowFlipping: allowFlipping,
    );

    final Resizer resizer = Resizer.from(resizeMode);
    final result = resizer.resize(
      explodedRect: explodedRect,
      clampingRect: clampingRect,
      handle: handle,
      constraints: constraints,
      initialRect: initialRect,
      flip: currentFlip,
      rotation: rotation,
      bindingStrategy: bindingStrategy,
    );

    final Box newRect = result.rect;
    final Box largestRect = result.largest;
    final Box newBoundingRect = calculateBoundingRect(
      rotation: rotation,
      unrotatedBox: newRect,
    );

    // Detect terminal resizing, where the resizing reached a hard limit.
    final terminalResult = checkForTerminalSizes(
      rect: newRect,
      initialRect: initialRect,
      clampingRect: clampingRect,
      rotation: rotation,
      constraints: constraints,
      handle: handle,
      bindingStrategy: bindingStrategy,
    );

    return ResizeResult(
      rect: newRect,
      oldRect: initialRect,
      boundingRect: newBoundingRect,
      oldBoundingRect: initialBoundingRect,
      flip: currentFlip * initialFlip,
      resizeMode: resizeMode,
      delta: delta,
      handle: handle,
      rawSize: newRect.size,
      largestRect: largestRect,
      minWidthReached: terminalResult.minWidthReached,
      maxWidthReached: terminalResult.maxWidthReached,
      minHeightReached: terminalResult.minHeightReached,
      maxHeightReached: terminalResult.maxHeightReached,
    );
  }

  /// Checks if the [rect] has reached a terminal size.
  /// Terminal size is when the rect has reached the min or max size according
  /// to the constraints defined by the [constraints] and [clampingRect].
  static ({
    bool minWidthReached,
    bool maxWidthReached,
    bool minHeightReached,
    bool maxHeightReached
  }) checkForTerminalSizes({
    required Box rect,
    required Box initialRect,
    required Box clampingRect,
    required double rotation,
    required Constraints constraints,
    required HandlePosition handle,
    required BindingStrategy bindingStrategy,
  }) {
    final initialBoundingRect = calculateBoundingRect(
      rotation: rotation,
      unrotatedBox: initialRect,
    );
    final boundingRect = calculateBoundingRect(
      rotation: rotation,
      unrotatedBox: rect,
    );
    final initialBindingWidth = bindingStrategy == BindingStrategy.originalBox
        ? initialRect.width
        : initialBoundingRect.width;
    final initialBindingHeight = bindingStrategy == BindingStrategy.originalBox
        ? initialRect.height
        : initialBoundingRect.height;

    final bindingWidth = bindingStrategy == BindingStrategy.originalBox
        ? rect.width
        : boundingRect.width;
    final bindingHeight = bindingStrategy == BindingStrategy.originalBox
        ? rect.height
        : boundingRect.height;

    bool minWidthReached = false;
    bool maxWidthReached = false;
    bool minHeightReached = false;
    bool maxHeightReached = false;
    if (handle.influencesHorizontal) {
      if (bindingWidth <= initialBindingWidth &&
          bindingWidth == constraints.minWidth) {
        minWidthReached = true;
      }
      if (bindingWidth >= initialBindingWidth &&
          (bindingWidth == constraints.maxWidth ||
              bindingWidth == clampingRect.width)) {
        maxWidthReached = true;
      }
    }
    if (handle.influencesVertical) {
      if (bindingHeight <= initialBindingHeight &&
          bindingHeight == constraints.minHeight) {
        minHeightReached = true;
      }
      if (bindingHeight >= initialBindingHeight &&
          (bindingHeight == constraints.maxHeight ||
              bindingHeight == clampingRect.height)) {
        maxHeightReached = true;
      }
    }

    return (
      minWidthReached: minWidthReached,
      maxWidthReached: maxWidthReached,
      minHeightReached: minHeightReached,
      maxHeightReached: maxHeightReached,
    );
  }

  static Box _applyDelta({
    required Box initialRect,
    required HandlePosition handle,
    required Vector2 delta,
    required ResizeMode resizeMode,
    required bool allowFlipping,
  }) {
    double left;
    double top;
    double right;
    double bottom;

    left = initialRect.left + (handle.influencesLeft ? delta.x : 0);
    top = initialRect.top + (handle.influencesTop ? delta.y : 0);
    right = initialRect.right + (handle.influencesRight ? delta.x : 0);
    bottom = initialRect.bottom + (handle.influencesBottom ? delta.y : 0);

    double width = right - left;
    double height = bottom - top;

    if (allowFlipping) {
      width = width.abs();
      height = height.abs();
    } else {
      // If not flipping, we need to make sure the width and height are
      // positive which would imply that the left and top are less than
      // the right and bottom respectively stopping rect from flipping.
      width = width.clamp(0, double.infinity);
      height = height.clamp(0, double.infinity);
    }

    // If in symmetric scaling mode, utilize width and height to constructor
    // the new rect from its center.
    if (resizeMode.hasSymmetry) {
      // symmetric resizing is not affected if flipping is disabled.
      final widthDelta = (initialRect.width - width) / 2;
      final heightDelta = (initialRect.height - height) / 2;
      left = initialRect.left + widthDelta;
      top = initialRect.top + heightDelta;
      right = initialRect.right - widthDelta;
      bottom = initialRect.bottom - heightDelta;
    } else if (!allowFlipping) {
      // If not flipping, then we know that handles are not allowed to
      // cross the opposite one. So we use handle with width and height
      // instead of left, top, right, bottom to construct the new rect.
      return Box.fromHandle(
        handle.anchor(initialRect),
        handle,
        width,
        height,
      );
    }

    return Box.fromLTRB(
      min(left, right),
      min(top, bottom),
      max(left, right),
      max(top, bottom),
    );
  }

  /// Rotates a point [point] around [origin] by the given [radians] and returns
  /// the new coordinates as a [Vec].
  static Vector2 rotatePointAroundVec(
      Vector2 origin, double radians, Vector2 point) {
    final transform = Matrix4.translationValues(origin.x, origin.y, 0)
      ..rotateZ(radians)
      ..translate(-origin.x, -origin.y, 0);

    final rotated = transform.applyToVector3Array([point.x, point.y, 0]);
    return Vector2(rotated[0], rotated[1]);
  }

  static Vector2 calculateUnrotatedPos(
      Box unrotatedRect, double radians, Vector2 newPos, Dimension newSize) {
    // This was our old rotated position.
    final oldRotatedXY = rotatePointAroundVec(
        unrotatedRect.center, radians, unrotatedRect.topLeft);
    // This is how the rotated position changes in parents system.
    final sinA = sin(-radians);
    final cosA = cos(-radians);
    final xChange = cosA * newPos.x + sinA * newPos.y;
    final yChange = cosA * newPos.y - sinA * newPos.x;
    // Node's new position in parent's system accounting for the changes:
    final newRotatedXY = oldRotatedXY + Vector2(xChange, yChange);
    // We need to rotate this back because we're interested in the new
    // unrotated position, not the rotated one.
    // For this we need the new center.
    final newRotatedBR = newRotatedXY +
        Vector2(cosA * newSize.width + sinA * newSize.height,
            cosA * newSize.height - sinA * newSize.width);
    final newCenter = Box.fromLTRB(
            newRotatedXY.x, newRotatedXY.y, newRotatedBR.x, newRotatedBR.y)
        .center;
    // Now we can rotate topLeft back.
    return rotatePointAroundVec(newCenter, -radians, newRotatedXY);
  }

  static Box calculateBoundingRect({
    required double rotation,
    required Box unrotatedBox,
  }) {
    final Vector2 center = unrotatedBox.center;

    // 𝑎cos𝜃+𝑏sin𝜃,
    final double boundingWidth = unrotatedBox.width * cos(rotation) +
        unrotatedBox.height * sin(rotation);

    // 𝑎sin𝜃+𝑏cos𝜃.
    final double boundingHeight = unrotatedBox.width * sin(rotation) +
        unrotatedBox.height * cos(rotation);

    final Box explodedRect = Box.fromCenter(
      center: center,
      width: boundingWidth,
      height: boundingHeight,
    );

    return explodedRect;
  }

  static Box calculateUnrotatedRect({
    required Box boundingBox,
    required double rotation,
    required double aspectRatio,
  }) {
    final Vector2 center = boundingBox.center;

    final double width = boundingBox.width * cos(-rotation) +
        boundingBox.height * sin(-rotation);

    // derive from aspect ratio.
    final double height = width / aspectRatio;

    final Box unrotatedRect = Box.fromCenter(
      center: center,
      width: width,
      height: height,
    );

    return unrotatedRect;
  }
}
