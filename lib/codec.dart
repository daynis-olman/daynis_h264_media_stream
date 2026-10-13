/// Pure-Dart H.264 stream tooling with no Flutter dependency.
///
/// Use this library in Dart command-line tools, servers or tests to parse
/// multipart or Annex-B H.264 streams, inspect SPS data, and mux fragmented
/// MP4. Flutter apps can import
/// `package:daynis_h264_media_stream/daynis_h264_media_stream.dart`, which
/// re-exports everything here.
library;

export 'src/h264/access_unit.dart' show AccessUnit, AccessUnitAssembler;
export 'src/h264/annexb_splitter.dart' show AnnexBSplitter;
export 'src/h264/h264_stream_parser.dart' show H264StreamParser;
export 'src/h264/nal_unit.dart' show NalUnit, NalUnitType;
export 'src/h264/sps.dart' show SpsInfo;
export 'src/mp4/fmp4_muxer.dart' show Fmp4Muxer, Fmp4Sample;
export 'src/multipart/multipart_demuxer.dart'
    show MultipartDemuxer, MultipartPart, multipartBoundary;
export 'src/multipart/multipart_stream.dart' show connectMultipart;
export 'src/transport/byte_stream.dart' show H264StreamException;
