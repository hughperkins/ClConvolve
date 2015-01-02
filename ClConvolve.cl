// Copyright Hugh Perkins 2014 hughperkins at gmail
//
// This Source Code Form is subject to the terms of the Mozilla Public License, 
// v. 2.0. If a copy of the MPL was not distributed with this file, You can 
// obtain one at http://mozilla.org/MPL/2.0/.

// expected defines:
// one of: [ TANH | RELU | LINEAR ]
// BIASED (or not)

#ifdef TANH
    #define ACTIVATION_FUNCTION(output) tanh(output)
    #define ACTIVATION_DERIV(output) 1 - output * output
#elif defined RELU
    #define ACTIVATION_FUNCTION(output) output> 0 ? output : 0
    #define ACTIVATION_DERIV(output) output > 0 ? 1 : 0
#elif defined LINEAR
    #define ACTIVATION_FUNCTION(output) output
    #define ACTIVATION_DERIV(output) 1
#endif
    
void kernel convolve_ints( global const int *p_boardSize, global const int *p_filterSize,
      global const int *image, global const int *filter, global int *result ) {
    int id = get_global_id(0);
    int boardSize = p_boardSize[0];
    int filterSize = p_filterSize[0];
    int boardOffset = id / (boardSize * boardSize ) * (boardSize * boardSize );
    int localid = id % (boardSize * boardSize );
    int row = localid / boardSize;
    int col = localid % boardSize;
    int halfFilterSize = filterSize >> 1;
    int sum = 0;
    int minm = max( -halfFilterSize, -row );
    int maxm = min( halfFilterSize, boardSize - 1 - row );
    int minn = max( -halfFilterSize, -col );
    int maxn = min( halfFilterSize, boardSize - 1 - col );
    int m = minm;
    while( m <= maxm ) {
        int x = ( row + m );
        int xboard = boardOffset + x * boardSize;
        int filterrowoffset = (m+halfFilterSize) * filterSize + halfFilterSize;
        int n = minn;
        while( n <= maxn ) {
            int y = col + n;
            sum += image[ xboard + y] * filter[ filterrowoffset + n ];
            n++;
        }
        m++;
    }
    result[id] = sum;
}

void kernel convolve_floats( global const int *p_boardSize, global const int *p_filterSize,
      global const float *image, global const float *filter, global float *result ) {
    int id = get_global_id(0);
    int boardSize = p_boardSize[0];
    int filterSize = p_filterSize[0];
    int boardOffset = id / (boardSize * boardSize ) * (boardSize * boardSize );
    int localid = id % (boardSize * boardSize );
    int row = localid / boardSize;
    int col = localid % boardSize;
    int halfFilterSize = filterSize >> 1;
    float sum = 0;
    int minm = max( -halfFilterSize, -row );
    int maxm = min( halfFilterSize, boardSize - 1 - row );
    int minn = max( -halfFilterSize, -col );
    int maxn = min( halfFilterSize, boardSize - 1 - col );
    int m = minm;
    while( m <= maxm ) {
        int x = ( row + m );
        int xboard = boardOffset + x * boardSize;
        int filterrowoffset = (m+halfFilterSize) * filterSize + halfFilterSize;
        int n = minn;
        while( n <= maxn ) {
            int y = col + n;
            sum += image[ xboard + y] * filter[ filterrowoffset + n ];
            n++;
        }
        m++;
    }
    result[id] = sum;
}

void kernel convolve_imagecubes_int( global const int *p_numInputPlanes, global const int *p_numFilters, 
      global const int *p_boardSize, global const int *p_filterSize,
      global const int *images, global const int *filters, global int *results ) {
    int globalId = get_global_id(0);

    int numInputPlanes = p_numInputPlanes[0];
    int numFilters = p_numFilters[0];
    int boardSize = p_boardSize[0];
    int filterSize = p_filterSize[0];
    int boardSizeSquared = boardSize * boardSize;

    int outputBoard2Id = globalId / boardSizeSquared;
    int filterId = outputBoard2Id % numFilters;
    int inputBoard3Id = outputBoard2Id / numFilters;

    int filterOffset = filterId * filterSize * filterSize;
    int inputBoard3Offset = inputBoard3Id * numInputPlanes * boardSizeSquared;

    // intraboard coords
    int localid = globalId % boardSizeSquared;
    int row = localid / boardSize;
    int col = localid % boardSize;

    int halfFilterSize = filterSize >> 1;
    int sum = 0;
    int minm = max( -halfFilterSize, -row );
    int maxm = min( halfFilterSize, boardSize - 1 - row );
    int minn = max( -halfFilterSize, -col );
    int maxn = min( halfFilterSize, boardSize - 1 - col );
    int plane = 0;
    while( plane < numInputPlanes ) {
        int inputBoardOffset = inputBoard3Offset + plane * boardSizeSquared;
        int filterPlaneOffset = filterOffset + plane * filterSize * filterSize;
        int m = minm;
        while( m <= maxm ) {
            int y = row + m;
            int inputboardrowoffset = inputBoardOffset + y * boardSize;
            int filterrowoffset = filterPlaneOffset + (m+halfFilterSize) * filterSize + halfFilterSize;
            int n = minn;
            while( n <= maxn ) {
                int x = col + n;
                sum += images[ inputboardrowoffset + x] * filters[ filterrowoffset + n ];
                n++;
            }
            m++;
        }
        plane++;
    }
    results[globalId] = sum;
}

// receive images as a stack of images
// globalid = n * numfilters * boardsize * boardsize + filter * boardsize * boardsize + imagerow * boardsize + imagecol
//                                 globalid              globalid
//  inputboard3 1 inputboard2 1----filter 1             -> outputboard2 1   outputboard3 1
//                inputboard2 2_/\_filter 2             -> outputboard2 2
//  inputboard3 2 inputboard2 3    filter 1             -> outputboard2 3   outputboard3 2
//                inputboard2 4    filter 2             -> outputboard2 4
//
// each outputboard is only written once, by a combination of:
// - one inputboard3
// - one filter
// each inputboard3 is mapped to each filter once, each time writing to one outputboard
//
// images is:
//       numimages * numinputplanes * boardsizesquared
// filters is:
//       numfilters * numinputplanes * filtersizesquared
// outputs is:
//       numimages * numfilters * outputboardsizesquared

// images are organized like [imageId][plane][row][col]
// filters are organized like [filterid][plane][filterrow][filtercol]
// results are organized like [imageid][filterid][row][col]
void kernel convolve_imagecubes_float( 
      const int numInputPlanes, const int numFilters, 
      const int boardSize, const int filterSize,
      global const float *images, global const float *filters, global float *results ) {
    int globalId = get_global_id(0);

    int boardSizeSquared = boardSize * boardSize;

    int outputBoard2Id = globalId / boardSizeSquared;
    int filterId = outputBoard2Id % numFilters;
    int inputBoard3Id = outputBoard2Id / numFilters;

    int filterOffset = filterId * filterSize * filterSize;
    int inputBoard3Offset = inputBoard3Id * numInputPlanes * boardSizeSquared;

    // intraboard coords
    int localid = globalId % boardSizeSquared;
    int row = localid / boardSize;
    int col = localid % boardSize;

    int halfFilterSize = filterSize >> 1;
    float sum = 0;
    // m should vary from -halfFilterSize through 0 to halfFilterSize 
    // n too...
    int minm = max( -halfFilterSize, -row );
    int maxm = min( halfFilterSize, boardSize - 1 - row );
    int minn = max( -halfFilterSize, -col );
    int maxn = min( halfFilterSize, boardSize - 1 - col );
    int inputPlane = 0;
    while( inputPlane < numInputPlanes ) {
        int inputBoardOffset = inputBoard3Offset + inputPlane * boardSizeSquared;
        int m = minm;
        while( m <= maxm ) {
            int y = row + m;
            int inputboardrowoffset = inputBoardOffset + y * boardSize;
            int filterrowoffset = filterOffset + (m+halfFilterSize) * filterSize + halfFilterSize;
            int n = minn;
            while( n <= maxn ) {
                int x = col + n;
                sum += images[ inputboardrowoffset + x] * filters[ filterrowoffset + n ];
                n++;
            }
            m++;
        }
        inputPlane++;
    }

    results[globalId] = sum;
}

void kernel convolve_imagecubes_float_nopadzeros( 
      const int numInputPlanes, const int numFilters, 
      const int inputBoardSize, const int filterSize,
      global const float *images, global const float *filters, global float *results ) {
    int globalId = get_global_id(0);

    int inputBoardSizeSquared = inputBoardSize * inputBoardSize;
    int outputBoardSize = inputBoardSize - filterSize + 1;
    int outputBoardSizeSquared = outputBoardSize * outputBoardSize;

    int outputBoard2Id = globalId / outputBoardSizeSquared;
    int filterId = outputBoard2Id % numFilters;
    int inputBoard3Id = outputBoard2Id / numFilters;

    int filterOffset = filterId * filterSize * filterSize;
    int inputBoard3Offset = inputBoard3Id * numInputPlanes * inputBoardSizeSquared;

    // intraboard coords
    int localid = globalId % outputBoardSizeSquared;
    int outputRow = localid / outputBoardSize;
    int outputCol = localid % outputBoardSize;

    int halfFilterSize = filterSize >> 1;
    float sum = 0;
    int minm = -halfFilterSize;
    int maxm = halfFilterSize;
    int minn = -halfFilterSize;
    int maxn = halfFilterSize;
    int inputPlane = 0;
    while( inputPlane < numInputPlanes ) {
        int inputBoardOffset = inputBoard3Offset + inputPlane * inputBoardSizeSquared;
        int m = minm;
        while( m <= maxm ) {
            int inputRow = outputRow + m + halfFilterSize;
            int inputboardrowoffset = inputBoardOffset + inputRow * inputBoardSize;
            int filterrowoffset = filterOffset + (m+halfFilterSize) * filterSize + halfFilterSize;
            int n = minn;
            while( n <= maxn ) {
                int inputCol = outputCol + n + halfFilterSize;
                sum += images[ inputboardrowoffset + inputCol] * filters[ filterrowoffset + n ];
                n++;
            }
            m++;
        }
        inputPlane++;
    }
    results[globalId] = sum;
}

// images are organized like [imageId][plane][row][col]
// filters are organized like [filterid][inplane][filterrow][filtercol]
// results are organized like [imageid][filterid][row][col]
// global id is organized like results, ie: [imageid][filterid][row][col]
#ifdef ACTIVATION_FUNCTION // protect against not defined
void kernel convolve_imagecubes_float2( const int numExamples,
      const int numInputPlanes, const int numFilters, 
      const int inputBoardSize, const int filterSize, const int padZeros,
      global const float *images, global const float *filters, 
#ifdef BIASED
global const float*biases, 
#endif
    global float *results ) {
    int globalId = get_global_id(0);

    const int evenPadding = filterSize % 2 == 0 ? 1 : 0;

    int inputBoardSizeSquared = inputBoardSize * inputBoardSize;
    int outputBoardSize = padZeros ? inputBoardSize + evenPadding : inputBoardSize - filterSize + 1;
    int outputBoardSizeSquared = outputBoardSize * outputBoardSize;
    int filterSizeSquared = filterSize * filterSize;

    int outputBoard2Id = globalId / outputBoardSizeSquared;
    int exampleId = outputBoard2Id / numFilters;
    int filterId = outputBoard2Id % numFilters;

    if( exampleId >= numExamples ) {
        return;
    }

    int inputCubeOffset = exampleId * numInputPlanes * inputBoardSizeSquared;
    int filterCubeOffset = filterId * numInputPlanes * filterSizeSquared;

    // intraboard coords
    int localid = globalId % outputBoardSizeSquared;
    int outputRow = localid / outputBoardSize;
    int outputCol = localid % outputBoardSize;

    int halfFilterSize = filterSize >> 1;
    float sum = 0;
    // for odd, boardsize and filtersize 3, padZeros = 0:
    // output is a single square
    // m and n should vary between -1,0,1
    // for even, boardsize and filtersize 2, padzeros = 0
    // output is a single square, which we can position at topleft or bottomrigth
    // lets position it in bottomright
    // then m and n should vary as -1,0
    //
    // for even, boardsize and filtersize 2, padzeros = 1
    // output is 2 by 2
    // well... if it is even:
    // - if we are not padding zeros, then we simply move our filter around the board somehow
    // - if we are padding zeros, then we conceptually pad the bottom and right edge of the board with zeros by 1
    // filtersize remains the same
    //      m will vary as -1,0,1
    //       outputrow is fixed by globalid
    //       inputrow should be unchanged...
    // padzeros = 0:
    //  x x .  . . .
    //  x x .  . x x
    //  . . .  . x x
    // when filtersize even:
    //    new boardsize = oldboardsize - filtersize + 1
    // when filtersize odd:
    //    x x x .
    //    x x x .
    //    x x x .
    //    . . . .
    //    new boardsize = oldboardsize - filtersize + 1
    // padzeros = 1:
    // x x
    // x x . .   x x .    . . .     . . .
    //   . . .   x x .    . x x     . . .
    //   . . .   . . .    . x x     . . x x
    // outrow=0 outrow=1  outrow=2      x x
    // outcol=0 outcol=1  outcol=2    outrow=3
    //                                outcol=3
    // when filtersize is even, and padzeros, boardsize grows by 1 each time...
    //    boardsize = oldboardsize + 1
    // when filtersize is odd
    //  x x x 
    //  x x x .   x x x    . . .
    //  x x x .   x x x    . x x x
    //    . . .   x x x    . x x x
    //                       x x x
    //  boardsize = oldboardsize
    int minm = padZeros ? max( -halfFilterSize, -outputRow ) : -halfFilterSize;
    int maxm = padZeros ? min( halfFilterSize - evenPadding, outputBoardSize - 1 - outputRow  - evenPadding) : halfFilterSize - evenPadding;
    int minn = padZeros ? max( -halfFilterSize, -outputCol ) : - halfFilterSize;
    int maxn = padZeros ? min( halfFilterSize - evenPadding, outputBoardSize - 1 - outputCol - evenPadding) : halfFilterSize - evenPadding;
    int inputPlane = 0;
//    float probe = 0;
    while( inputPlane < numInputPlanes ) {
        int inputBoardOffset = inputCubeOffset + inputPlane * inputBoardSizeSquared;
        int filterBoardOffset = filterCubeOffset + inputPlane * filterSizeSquared;
        int m = minm;
        while( m <= maxm ) {
            int inputRow = outputRow + m + ( padZeros ? 0 : halfFilterSize );
            int inputboardrowoffset = inputBoardOffset + inputRow * inputBoardSize;
            int filterrowoffset = filterBoardOffset + (m+halfFilterSize) * filterSize + halfFilterSize;
            int n = minn;
            while( n <= maxn ) {
                int inputCol = outputCol + n + ( padZeros ? 0 : halfFilterSize );
                sum += images[ inputboardrowoffset + inputCol] * filters[ filterrowoffset + n ];
//                probe += 10000 * pown(100, inputPlane) *( inputboardrowoffset + inputCol );
            //    probe += pown(100, inputPlane) *( images[inputboardrowoffset + inputCol] );
                //probe += pown(100, inputPlane) *( filterrowoffset + n );
             //   probe += pown(1000, inputPlane) *( floor(filters[ filterrowoffset + n ]*100)/100 );

//                sum = filters[filterrowoffset + n];
                //sum = filterrowoffset;
                n++;
            }
            m++;
        }
//        probe += pown(100, inputPlane ) * filterBoardOffset;
        inputPlane++;
    }
//     probe = exampleId * 100 + filterCubeOffset;

#ifdef BIASED
    sum += biases[filterId];
#endif
    results[globalId] = ACTIVATION_FUNCTION(sum);
//    results[0] = 1234.0;
//     results[1024+globalId] = maxn;
//     results[1] = maxMm;
//     results[2] = minm;
}
#endif

// images are organized like [imageId][plane][row][col]    128*32*19*19=1,500,000
// filters are organized like [filterid][inplane][filterrow][filtercol] 32*32*5*5=25600 = 100k bytes, or 3.2KB per filter
// results are organized like [imageid][filterid][row][col]   128*32*19*19=1,500,000 = 6MB, or 46KB per image,
//                                                            
//                  if w updates are per image,then 25600*128 = 3.3 million
// eg 32 * 32 * 5 * 5 = 25600 ...
// then we are aggregating over [outRow][outCol][n]
//      eg 19 * 19 * 128 = 46208
// derivtype: 0=relu 1=tanh
// outboards(eg 128x32x28x28), errors (eg 128x28x28), upstreamboards (eg 128x32x28x28) => weightchanges (eg 32x32x28x28)
// if break for per-example, per-filter:
// outboard(eg 28x28), error (28x28), upstreamboard(32x28x28) => weightchanges(32x5x5)
//             784 3k         784 3k                 25088 100k                800 3k
// if break for per-filter:
// outboard(eg 128x28x28), error (128x28x28), upstreamboard(128x32x28x28) => weightchanges(32x32x5x5)
//                350k           350k                 12.8MB                   100k
// if break for per-example:
// outboard(eg 28x28), error (28x28), upstreamboard(32x28x28) => weightchanges(32x5x5)
//                3k             3k                 100k                       3k
//    note that weightchanges will need to be summed over 128 input boards
//
// globalid is for: [outPlane][upstreamPlane][filterRow][filterCol]
// per-thread looping over [n][outRow][outCol]
#ifdef ACTIVATION_DERIV // protect against if activation_function not defined
void kernel backprop_floats( const float learningRateMultiplier,
        const int batchSize, const int upstreamNumPlanes, const int numPlanes, 
         const int upstreamBoardSize, const int filterSize, const int outBoardSize, const int padZeros, 
         global const float *images, global const float *results, global const float *errors, global float *weightChanges ) {
    int globalId = get_global_id(0);

    int filterSizeSquared = filterSize * filterSize;

    int IntraFilterOffset = globalId % filterSizeSquared;
    int filterRow = IntraFilterOffset / filterSize;
    int filterCol = IntraFilterOffset % filterSize;

    int filter2Id = globalId / filterSizeSquared;
    int outPlane = filter2Id / upstreamNumPlanes;
    int upstreamPlane = filter2Id % upstreamNumPlanes;

    const int halfFilterSize = filterSize >> 1;
    const int margin = padZeros ? halfFilterSize : 0;
    float thiswchange = 0;
    // weights:     [outPlane][upstreamPlane][filterRow][filterCol]
    //       aggregate over:  [outRow][outCol][n]
    for( int n = 0; n < batchSize; n++ ) {
        for( int outRow = 0; outRow < outBoardSize; outRow++ ) {
            int upstreamRow = outRow - margin + filterRow;
            for( int outCol = 0; outCol < outBoardSize; outCol++ ) {
                int upstreamCol = outCol - margin + filterCol;
                int resultIndex = ( ( n * numPlanes 
                          + outPlane ) * outBoardSize
                          + outRow ) * outBoardSize
                          + outCol;
                float error = errors[resultIndex];
                float actualOutput = results[resultIndex];
                float activationDerivative = ACTIVATION_DERIV( actualOutput);
                int upstreamDataIndex = ( ( n * upstreamNumPlanes 
                                 + upstreamPlane ) * upstreamBoardSize
                                 + upstreamRow ) * upstreamBoardSize
                                 + upstreamCol;
                float upstreamResult = images[upstreamDataIndex];
                float thisimagethiswchange = upstreamResult * activationDerivative *
                    error;
                thiswchange += thisimagethiswchange;
            }
        }
    }
    // weights:     [outPlane][upstreamPlane][filterRow][filterCol]
    //       aggregate over:  [outRow][outCol][n]
    weightChanges[ globalId ] = - learningRateMultiplier * thiswchange;
}
#endif

// if break for per-example, per-filter:
// outboard(eg 28x28), error (28x28), upstreamboard(32x28x28) => weightchanges(32x5x5)
//             784 3k         784 3k                 25088 100k                800 3k
// if break for per-example, per-filter, per-upstream:
// outboard(eg 28x28), error (28x28), upstreamboard(28x28) => weightchanges(5x5)
//             784 3k         784 3k                 784 3k                 25
// n * outplane = 128 * 32 = 4096   , then loop over: [upstreamrow][upstreamcol]
// in this version, globalid is structured as: [n][outPlane][upstreamPlane][upstreamRow][upstreamCol]
//                  localid is structured as [upstreamRow][upstreamCol]
//                   can each thread should loop over .... : [filterRow][filterCol]
//        (outRow/outCol are locked to upstreamRow/upstreamCol)
// w is [filterRow][filterCol]
// this assumes that filterSizeSquared will fit into one workgroup
//  - which is true for Go-boards, but not for MNIST :-P
//      - so we will test with cropped MNIST images, 19x19, same as go boards :-)
#ifdef ACTIVATION_DERIV // protect against if activation_function not defined
void kernel backprop_floats_2( 
    const float learningRateMultiplier, const int batchSize, 
     global const float *upstreamBoardsGlobal, global const float *resultsGlobal, global const float *errorsGlobal,
     global float *weightChangesGlobal,
    local float *_upstreamBoard, local float *_resultBoard, local float *_errorBoard, 
    local float *_weightChanges, local float *_weightReduceArea ) {

        // required (minimum...) sizes for local arrays:
        // upstreamboard: upstreamBoardSizeSquared
        // resultboard: outBoardSizeSquared
        // errorBoard: outBoardSizeSquaread
        // weightChanges: filterSizeSquared
        // weightReduceArea: upstreamBoardSizeSquared, or workflowSize, to be decided :-)
    const int globalId = get_global_id(0);
    const int localId = get_local_id(0);
    const int workgroupSize = get_local_size(0);

    const int upstreamBoard2dId = globalId / gUpstreamBoardSizeSquared;
    const int upstreamPlane = upstreamBoard2dId % gUpstreamNumPlanes;
    const int outPlane2dId = upstreamBoard2dId / gUpstreamNumPlanes;
    const int n = outPlane2dId / gNumOutPlanes;
    const int outPlane = outPlane2dId % gNumOutPlanes;

    const int upstreamRow = localId / gUpstreamBoardSize;
    const int upstreamCol = localId % gUpstreamBoardSize;

    // each localid corresponds to one [upstreamRow][upstreamCol] combination
    // we assume that:
    // filterSize <= upstreamBoardSize (reasonable... :-) )
    // outBoardSize <= upstreamBoardSize (true... unless we have a filter with even size, and padZeros = true )
    const int upstreamBoardGlobalOffset = ( n * gUpstreamNumPlanes + upstreamPlane ) * gUpstreamBoardSizeSquared;
    if( localId < gUpstreamBoardSizeSquared ) {
        _upstreamBoard[localId] = upstreamBoardsGlobal[upstreamBoardGlobalOffset + localId];
    }
    int resultBoardGlobalOffset = ( n * gNumOutPlanes + outPlane ) * gOutBoardSizeSquared;
    if( localId < gOutBoardSizeSquared ) {
        _resultBoard[localId ] = resultsGlobal[resultBoardGlobalOffset + localId];
        _errorBoard[localId ] = errorsGlobal[resultBoardGlobalOffset + localId];
    }
    if( localId < gFilterSizeSquared ) {
        _weightChanges[localId] = 0;
    }
    barrier(CLK_LOCAL_MEM_FENCE);

    // now we loop over the filter, and the output board...
    for( int filterRow = 0; filterRow < gFilterSize; filterRow++ ) {
        int outRow = upstreamRow + gMargin - filterRow;
        for( int filterCol = 0; filterCol < gFilterSize; filterCol++ ) {
            int outCol = upstreamCol + gMargin - filterCol;
//            float thiswchange = 0;
            int resultIndex = outRow * gOutBoardSize + outCol;
            float error = _errorBoard[resultIndex];
            float actualOutput = _resultBoard[resultIndex];
            float activationDerivative = ACTIVATION_DERIV( actualOutput);
            int upstreamDataIndex = upstreamRow * gUpstreamBoardSize + upstreamCol;
            float upstreamResult = _upstreamBoard[upstreamDataIndex];
            float thisimagethiswchange = upstreamResult * activationDerivative * error;
            _weightReduceArea[localId] = localId < gUpstreamBoardSizeSquared ? thisimagethiswchange : 0;
/*
            barrier(CLK_LOCAL_MEM_FENCE);
            for( int offset = workgroupSize / 2; offset > 0; offset >>= 1 ) {
//                float other = _weightReduceArea[ localId + offset ];
//                float mine = _weightReduceArea[ localId ];
                if( localId < offset ) {
                    _weightReduceArea[localId] = _weightReduceArea[ localId ] + _weightReduceArea[ localId + offset ];
                }
                barrier(CLK_LOCAL_MEM_FENCE);
            }
            if( localId == 0 ) { // maybe can remove this if? leave for now, so fewer bugs :-)
                _weightChanges[filterRow * gFilterSize + filterCol] = _weightReduceArea[0];
            }
//            flothiswchange += thisimagethiswchange;
//            _weightChanges*/
        }
    }
    // oh, we have to reduce again, over n and stuff...
    // let's test with a single example and upplane and filter first :-)
    // so, we just copy it in for now :-)
    if( localId < gFilterSizeSquared ) {
//        weightChangesGlobal[ localId ] = - learningRateMultiplier * _weightChanges[ localId ];
        weightChangesGlobal[globalId] = - learningRateMultiplier * _weightReduceArea[localId];
    }   
//    weightChangesGlobal[globalId] = resultsGlobal[localId];
    // weights:     [outPlane][upstreamPlane][filterRow][filterCol]
    //       aggregate over:  [outRow][outCol][n]
//    weightChanges[ globalId ] = - learningRateMultiplier * thiswchange;
}
#endif

// handle lower layer...
// errors for upstream look like [n][inPlane][inRow][inCol]
// need to aggregate over: [outPlane][outRow][outCol] (?)
// need to backprop errors along each possible weight
// each upstream feeds to:
//    - each of our filters (so numPlanes filters)
//    - each of our outpoint points (so boardSize * boardSize)
// for our own backprop, we updated weights for:
//      [outPlane][inPlane][filterRow][filtercol]
//    aggregating over: [n][outRow][outCol]
// errors are provider per [n][inPlane][inRow][inCol]
// globalid is structured as: [n][upstreamPlane][upstreamRow][upstreamCol]
void kernel calcErrorsForUpstream( 
        const int upstreamNumPlanes, const int upstreamBoardSize, const int filterSize, 
        const int outNumPlanes, const int outBoardSize,
        const int padZeros,
        global const float *weights, global const float *errors, global float *errorsForUpstream ) {
    int globalId = get_global_id(0);
    const int halfFilterSize = filterSize >> 1;
    const int margin = padZeros ? halfFilterSize : 0;

    const int upstreamBoardSizeSquared = upstreamBoardSize * upstreamBoardSize;
    const int upstreamBoard2dId = globalId / upstreamBoardSizeSquared;

    const int intraBoardOffset = globalId % upstreamBoardSizeSquared;
    const int upstreamRow = intraBoardOffset / upstreamBoardSize;
    const int upstreamCol = intraBoardOffset % upstreamBoardSize;

    const int upstreamPlane = upstreamBoard2dId % upstreamNumPlanes;
    const int n = upstreamBoard2dId / upstreamNumPlanes;

    float sumWeightTimesOutError = 0;
    // aggregate over [outPlane][outRow][outCol]
    for( int outPlane = 0; outPlane < outNumPlanes; outPlane++ ) {
        for( int outRow = 0; outRow < outBoardSize; outRow++ ) {
            // need to derive filterRow and filterCol, given outRow and outCol
            int filterRow = upstreamRow + margin - outRow;
            for( int outCol = 0; outCol < outBoardSize; outCol++ ) {
               // need to derive filterRow and filterCol, given outRow and outCol
                int filterCol = upstreamCol + margin - outCol;
                int resultIndex = ( ( n * outNumPlanes 
                          + outPlane ) * outBoardSize
                          + outRow ) * outBoardSize
                          + outCol;
                float thisError = errors[resultIndex];
                int thisWeightIndex = ( ( outPlane * upstreamNumPlanes
                                    + upstreamPlane ) * filterSize
                                    + filterRow ) * filterSize
                                    + filterCol;
                float thisWeight = weights[thisWeightIndex];
                float thisWeightTimesError = thisWeight * thisError;
                sumWeightTimesOutError += thisWeightTimesError;
            }
        }
    }
    errorsForUpstream[globalId] = sumWeightTimesOutError;
}

