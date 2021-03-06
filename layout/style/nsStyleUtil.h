/* -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
#ifndef nsStyleUtil_h___
#define nsStyleUtil_h___

#include "nsCoord.h"
#include "nsCSSProperty.h"
#include "gfxFontFeatures.h"
#include "nsIPrincipal.h"
#include "nsSubstring.h"

class nsCSSValue;
class nsStringComparator;
class nsIContent;
struct gfxFontFeature;
class nsCSSValueList;
template <class E> class nsTArray;

// Style utility functions
class nsStyleUtil {
public:

 static bool DashMatchCompare(const nsAString& aAttributeValue,
                                const nsAString& aSelectorValue,
                                const nsStringComparator& aComparator);

  // Append a quoted (with 'quoteChar') and escaped version of aString
  // to aResult.  'quoteChar' must be ' or ".
  static void AppendEscapedCSSString(const nsAString& aString,
                                     nsAString& aResult,
                                     PRUnichar quoteChar = '"');

  // Append the identifier given by |aIdent| to |aResult|, with
  // appropriate escaping so that it can be reparsed to the same
  // identifier.
  static void AppendEscapedCSSIdent(const nsAString& aIdent,
                                    nsAString& aResult);

  // Append a bitmask-valued property's value(s) (space-separated) to aResult.
  static void AppendBitmaskCSSValue(nsCSSProperty aProperty,
                                    int32_t aMaskedValue,
                                    int32_t aFirstMask,
                                    int32_t aLastMask,
                                    nsAString& aResult);

  static void AppendPaintOrderValue(uint8_t aValue, nsAString& aResult);

  static void AppendFontFeatureSettings(const nsTArray<gfxFontFeature>& aFeatures,
                                        nsAString& aResult);

  static void AppendFontFeatureSettings(const nsCSSValue& src,
                                        nsAString& aResult);

  // convert bitmask value to keyword name for a functional alternate
  static void GetFunctionalAlternatesName(int32_t aFeature,
                                          nsAString& aFeatureName);

  // Append functional font-variant-alternates values to string
  static void
  SerializeFunctionalAlternates(const nsTArray<gfxAlternateValue>& aAlternates,
                                nsAString& aResult);

  // List of functional font-variant-alternates values to feature/value pairs
  static void
  ComputeFunctionalAlternates(const nsCSSValueList* aList,
                              nsTArray<gfxAlternateValue>& aAlternateValues);

  /*
   * Convert an author-provided floating point number to an integer (0
   * ... 255) appropriate for use in the alpha component of a color.
   */
  static uint8_t FloatToColorComponent(float aAlpha)
  {
    NS_ASSERTION(0.0 <= aAlpha && aAlpha <= 1.0, "out of range");
    return NSToIntRound(aAlpha * 255);
  }

  /*
   * Convert the alpha component of an nscolor (0 ... 255) to the
   * floating point number with the least accurate *decimal*
   * representation that is converted to that color.
   *
   * Should be used only by serialization code.
   */
  static float ColorComponentToFloat(uint8_t aAlpha);

  /*
   * Does this child count as significant for selector matching?
   */
  static bool IsSignificantChild(nsIContent* aChild,
                                   bool aTextIsSignificant,
                                   bool aWhitespaceIsSignificant);
  /*
   *  Does this principal have a CSP that blocks the application of
   *  inline styles ? Returns false if application of the style should
   *  be blocked.
   *
   *  Note that the principal passed in here needs to be the principal
   *  of the document, not of the style sheet. The document's principal
   *  is where any Content Security Policy that should be used to
   *  block or allow inline styles will be located.
   */
  static bool CSPAllowsInlineStyle(nsIPrincipal* aPrincipal,
                                   nsIURI* aSourceURI,
                                   uint32_t aLineNumber,
                                   const nsSubstring& aStyleText,
                                   nsresult* aRv);

};


#endif /* nsStyleUtil_h___ */
