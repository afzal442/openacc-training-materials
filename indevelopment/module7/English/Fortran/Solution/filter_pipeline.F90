!
! Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!

module filter_pipeline_f90
  implicit none
  integer, parameter :: filtersize = 5
  real(8),dimension(filtersize,filtersize) :: filter = reshape( (/ 1, 1, 1, 1, 1,   &
                                                                   1, 2, 2, 2, 1,   &
                                                                   1, 2, 3, 2, 1,   &
                                                                   1, 2, 2, 2, 1,   &
                                                                   1, 1, 1, 1, 1/), &
                                                                   shape(filter) )
  !$acc declare copyin(filter)
  ! This should be 1 divided by the sum of values in filter
  real(8) :: scale = 1.0 / 35.0
  contains
    subroutine blur5_pipelined(imgData, outImg, w, h, c)
      use iso_c_binding
      implicit none
      integer(kind=c_char),dimension(c,w,h)     :: imgData, outImg
      integer(kind=c_long),value :: w, h, c
      integer(kind=c_long) :: x, y, fx, fy, ix, iy
      real(8) :: blue, green, red
      integer(kind=c_long) :: yblock, ystart, yend, blockSize, numBlocks = 32
      integer(kind=c_long) :: lastRow, lower, upper

      blockSize = (h + numBlocks - 1) / numBlocks
      lastrow = 0
      !$acc data create(imgData,outImg)
      do yblock = 0, numBlocks - 1
        ystart = yblock * blockSize + 1
        yend = min(ystart + blockSize, h)
        lower = lastrow
        upper = min(yend + (filtersize/2), h)
        if ( lower < upper ) then
          !$acc update device(imgData(:,:,lower:upper)) async(mod(yblock,2))
          lastrow = upper
        endif
        !$acc parallel loop collapse(2) private(red, blue, green, ix, iy) async(mod(yblock,2))
        do y=ystart, yend
          do x=1, w
            red   = 0.0
            blue  = 0.0
            green = 0.0
            !$acc loop seq
            do fy=1, filtersize
              iy = y - (filtersize/2) + fy - 1
              !$acc loop seq
              do fx=1, filtersize
                ix = x - (filtersize/2) + fx - 1
                if ( (iy > 0) .and. (ix > 0) .and. &
                     (iy <= h) .and. (ix <= w) ) then
                  blue  = blue  + filter(fx,fy) * real(imgData(1,ix,iy)+256)
                  green = green + filter(fx,fy) * real(imgData(2,ix,iy)+256)
                  red   = red   + filter(fx,fy) * real(imgData(3,ix,iy)+256)
                endif
              enddo
            enddo
            outImg(1, x, y) = 255 - int(scale * blue)
            outImg(2, x, y) = 255 - int(scale * green) 
            outImg(3, x, y) = 255 - int(scale * red)
          enddo
        enddo
        !$acc update self(outImg(:,:,ystart:yend)) async(mod(yblock,2))
      enddo
      !$acc wait
      !$acc end data
    end subroutine
end module
