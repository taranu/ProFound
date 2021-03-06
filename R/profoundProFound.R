.selectCoG=function(diffmat, threshold=1.05){
  IDmat=matrix(rep(1:dim(diffmat)[2],each=dim(diffmat)[1]),nrow=dim(diffmat)[1])
  logmat=diffmat>1 & diffmat<threshold
  IDfin=IDmat
  IDfin[logmat==FALSE]=NA
  NegFlux=which(diffmat<threshold^0.2,arr.ind=TRUE)
  if(length(NegFlux)>0){
    NegFlux[,2]=NegFlux[,2]-1
    IDfin[NegFlux]=IDmat[NegFlux]
    IDfin[NegFlux[NegFlux[,2]==0,1],1]=0
  }
  tempout=suppressWarnings(apply(IDfin,1,min,na.rm=TRUE))
  tempout[is.infinite(tempout)]=dim(diffmat)[2]
  tempout=tempout+1
  # tempout={}
  # for(i in 1:dim(diffmat)[1]){
  #   tempsel=which(diffmat[i,]>(threshold^0.1) & diffmat[i,]<threshold)+1
  #   if(length(tempsel)==0){
  #     if(any(diffmat[i,]<1, na.rm=TRUE)){
  #       tempsel=min(which(diffmat[i,]<1))
  #     }else{
  #       tempsel=which.min(diffmat[i,])
  #       if(length(tempsel)==0){
  #         tempsel=1
  #       }
  #     }
  #   }else{
  #     tempsel=min(tempsel)
  #   }
  #   tempout=c(tempout, tempsel)
  # }
  return=tempout
}

profoundProFound=function(image, segim, objects, mask, skycut=1, pixcut=3, tolerance=4, ext=2, sigma=1, smooth=TRUE, SBlim, size=5, shape='disc', iters=6, threshold=1.05, converge='flux', magzero=0, gain=NULL, pixscale=1, sky, skyRMS, redosky=TRUE, redoskysize=21, box=c(100,100), grid=box, type='bilinear', skytype='median', skyRMStype='quanlo', sigmasel=1, doclip=TRUE, shiftloc = FALSE, paddim = TRUE, header, verbose=FALSE, plot=FALSE, stats=TRUE, rotstats=FALSE, boundstats=FALSE, nearstats=boundstats, groupstats=boundstats, offset=1, haralickstats=FALSE, sortcol="segID", decreasing=FALSE, lowmemory=FALSE, keepim=TRUE, R50clean=0, ...){
  if(verbose){message('Running ProFound:')}
  timestart=proc.time()[3]
  call=match.call()
  if(length(image)>1e6){rembig=TRUE}else{rembig=FALSE}
  
  #Split out image and header parts of input:
  
  if(!missing(image)){
    if(any(names(image)=='imDat') & missing(header)){
      if(verbose){message('Supplied image contains image and header components')}
      header=image$hdr
      image=image$imDat
    }else if(any(names(image)=='imDat') & !missing(header)){
      if(verbose){message('Supplied image contains image and header but using specified header')}
      image=image$imDat
    }
    if(any(names(image)=='dat') & missing(header)){
      if(verbose){message('Supplied image contains image and header components')}
      header=image$hdr[[1]]
      header=data.frame(key=header[,1],value=header[,2], stringsAsFactors = FALSE)
      image=image$dat[[1]]
    }else if(any(names(image)=='dat') & !missing(header)){
      if(verbose){message('Supplied image contains image and header but using specified header')}
      image=image$dat[[1]]
    }
    if(any(names(image)=='image') & missing(header)){
      if(verbose){message('Supplied image contains image and header components')}
      header=image$header
      image=image$image
    }else if(any(names(image)=='image') & !missing(header)){
      if(verbose){message('Supplied image contains image and header but using specified header')}
      image=image$image
    }
  }
  
  if(verbose){message(paste('Supplied image is',dim(image)[1],'x',dim(image)[2],'pixels'))}
  
  #Treat image NAs as masked regions:
  
  if(!missing(mask)){
    mask[is.na(image)]=1
    image[is.na(image)]=0
  }else{
    if(any(is.na(image))){
      mask=matrix(0,dim(image)[1],dim(image)[2])
      mask[is.na(image)]=1
      image[is.na(image)]=0
    }
  }
  
  if(!missing(segim) & !missing(mask)){
    segim=segim*(1-mask) 
  }
  
  #Get the pixel scale, if possible and not provided:
  
  if(missing(pixscale) & !missing(header)){
    pixscale=getpixscale(header)
    if(verbose){message(paste('Extracted pixel scale from header provided:',round(pixscale,3),'asec/pixel'))}
  }else{
    if(verbose){message(paste('Using suggested pixel scale:',round(pixscale,3),'asec/pixel'))}
  }
  
  skyarea=prod(dim(image))*pixscale^2/(3600^2)
  if(verbose){message(paste('Supplied image is',round(dim(image)[1]*pixscale/60,3),'x',round(dim(image)[2]*pixscale/60,3),'amin, ', round(skyarea,3),'deg-sq'))}
  
  if(missing(objects)){
    if(!missing(segim)){
      objects=segim
      objects[objects != 0] = 1
    }
  }
  
  #Check for user provided sky, and compute if missing:
  
  hassky=!missing(sky)
  hasskyRMS=!missing(skyRMS)
  
  if((hassky==FALSE | hasskyRMS==FALSE) & missing(segim)){
    if(verbose){message(paste('Making initial sky map -',round(proc.time()[3]-timestart,3),'sec'))}
    roughsky=profoundMakeSkyGrid(image=image, objects=objects, mask=mask, box=box, grid=grid, type=type, shiftloc = shiftloc, paddim = paddim)
    if(hassky==FALSE){
      sky=roughsky$sky
      if(verbose){message(' - Sky statistics :')}
      if(verbose){print(summary(as.numeric(sky)))}
    }
    if(hasskyRMS==FALSE){
      skyRMS=roughsky$skyRMS
      if(verbose){message(' - Sky-RMS statistics :')}
      if(verbose){print(summary(as.numeric(skyRMS)))}
    }
  }else{
    if(verbose){message("Skipping making initial sky map - User provided sky and sky RMS, or user provided segim")}
  }
  
  #Make the initial segmentation map, if not provided.
  
  if(missing(segim)){
    if(verbose){message(paste('Making initial segmentation image -',round(proc.time()[3]-timestart,3),'sec'))}
    segim=profoundMakeSegim(image=image, objects=objects, mask=mask, tolerance=tolerance, ext=ext, sigma=sigma, smooth=smooth, pixcut=pixcut, skycut=skycut, SBlim=SBlim,  sky=sky, skyRMS=skyRMS, verbose=verbose, plot=FALSE, stats=FALSE)
    objects=segim$objects
    segim=segim$segim
  }else{
    if(verbose){message("Skipping making an initial segmentation image - User provided segim")}
  }
  
  if(any(segim>0)){
    if((hassky==FALSE | hasskyRMS==FALSE) & iters>0){
      if(verbose){message(paste('Doing initial aggressive dilation -',round(proc.time()[3]-timestart,3),'sec'))}
      objects_redo=profoundMakeSegimDilate(image=image, segim=objects, mask=mask, size=redoskysize, shape=shape, sky=sky, verbose=verbose, plot=FALSE, stats=FALSE, rotstats=FALSE)$objects
      if(verbose){message(paste('Making better sky map -',round(proc.time()[3]-timestart,3),'sec'))}
      bettersky=profoundMakeSkyGrid(image=image, objects=objects_redo, mask=mask, box=box, grid=grid, type=type, shiftloc = shiftloc, paddim = paddim)
      if(hassky==FALSE){
        sky=bettersky$sky
        if(verbose){message(' - Sky statistics :')}
        if(verbose){print(summary(as.numeric(sky)))}
      }
      if(hasskyRMS==FALSE){
        skyRMS=bettersky$skyRMS
        if(verbose){message(' - Sky-RMS statistics :')}
        if(verbose){print(summary(as.numeric(skyRMS)))}
      }
    }else{
      if(verbose){message("Skipping making better sky map - User provided sky and sky RMS or iters=0")}
    }
    
    if(iters>0){
      if(verbose){message(paste('Calculating initial segstats -',round(proc.time()[3]-timestart,3),'sec'))}
      segstats=profoundSegimStats(image=image, segim=segim, mask=mask, sky=sky, pixscale=pixscale)
      
      if(R50clean[1]!=0){
        badseg=segstats$R50<=R50clean
        segim[segim %in% segstats[badseg,'segID']]=0
        segstats=segstats[which(!badseg),]
      }
      
      compmat=cbind(segstats[,converge])
      segim_array=array(0, dim=c(dim(segim),iters+1))
      segim_array[,,1]=segim
      
      segim_orig=segim
      
      if(verbose){message('Doing dilations:')}
      
      for(i in 1:iters){
        if(verbose){message(paste('Iteration',i,'of',iters,'-',round(proc.time()[3]-timestart,3),'sec'))}
        segim=profoundMakeSegimDilate(image=image-sky, segim=segim_array[,,i], mask=mask, size=size, shape=shape, verbose=verbose, plot=FALSE, stats=TRUE, rotstats=FALSE)
        compmat=cbind(compmat, segim$segstats[,converge])
        segim_array[,,i+1]=segim$segim
      }
      
      if(verbose){message(paste('Finding CoG convergence -',round(proc.time()[3]-timestart,3),'sec'))}
      
      diffmat=rbind(compmat[,2:(iters+1)]/compmat[,1:(iters)])
      selseg=.selectCoG(diffmat, threshold)
      
      segim=segim$segim
      segim[]=0
      
      if(verbose){message(paste('Constructing final segim -',round(proc.time()[3]-timestart,3),'sec'))}
      for(i in 1:(iters+1)){
        select=segim_array[,,i] %in% segstats[selseg==i,'segID']
        segim[select]=segim_array[,,i][select]
      }
      
      if(rembig){
        rm(select)
        rm(segim_array)
        invisible(gc())
      }
      
      origfrac=compmat[,1]/compmat[cbind(1:length(selseg),selseg)]
      
      objects=segim
      objects[objects!=0]=1
      
      selseg=selseg-1
      
    }else{
      if(verbose){message('Iters set to 0 - keeping segim un-dilated')}
      segim_orig=segim
      selseg=0
      origfrac=1
    }
    
    if(redosky){
      if(redoskysize %% 2 == 0){redoskysize=redoskysize+1}
      if(verbose){message(paste('Doing final aggressive dilation -',round(proc.time()[3]-timestart,3),'sec'))}
      objects_redo=profoundMakeSegimDilate(image=image, segim=objects, mask=mask, size=redoskysize, shape=shape, sky=sky, verbose=verbose, plot=FALSE, stats=FALSE, rotstats=FALSE)$objects
      if(verbose){message(paste('Making final sky map -',round(proc.time()[3]-timestart,3),'sec'))}
      sky=profoundMakeSkyGrid(image=image, objects=objects_redo, mask=mask, box=box, grid=grid, type=type, skytype=skytype, skyRMStype=skyRMStype, sigmasel=sigmasel, doclip=doclip, shiftloc = shiftloc, paddim = paddim)
      skyRMS=sky$skyRMS
      sky=sky$sky
      if(verbose){message(' - Sky statistics :')}
      if(verbose){print(summary(as.numeric(sky)))}
      if(verbose){message(' - Sky-RMS statistics :')}
      if(verbose){print(summary(as.numeric(skyRMS)))}
    }else{
      if(verbose){message("Skipping making final sky map - redosky set to FALSE")}
      objects_redo=NULL
    }
    
    Norig=tabulate(segim_orig)
    
    if(lowmemory){
      image=image-sky
      sky=0
      skyRMS=0
      segim_orig=NULL
      objects=NULL
      objects_redo=NULL
      invisible(gc())
    }
    
    if(stats & !missing(image)){
      if(verbose){message(paste('Calculating final segstats for',length(which(tabulate(segim)>0)),'objects -',round(proc.time()[3]-timestart,3),'sec'))}
      if(verbose){message(paste(' - magzero =', round(magzero,3)))}
      if(verbose){
        if(is.null(gain)){
          message(paste(' - gain = NULL (ignored)'))
        }else{
          message(paste(' - gain =', round(gain,3)))
        }
      }
      if(verbose){message(paste(' - pixscale =', round(pixscale,3)))}
      if(verbose){message(paste(' - rotstats =', rotstats))}
      if(verbose){message(paste(' - boundstats =', boundstats))}
      segstats=profoundSegimStats(image=image, segim=segim, mask=mask, sky=sky, skyRMS=skyRMS, magzero=magzero, gain=gain, pixscale=pixscale, header=header, sortcol=sortcol, decreasing=decreasing, rotstats=rotstats, boundstats=boundstats, offset=offset)
      segstats=cbind(segstats, iter=selseg, origfrac=origfrac, Norig=Norig[segstats$segID])
      segstats=cbind(segstats, flag_keep=segstats$origfrac>= median(segstats$origfrac[segstats$iter==iters]) | segstats$iter<iters)
    }else{
      if(verbose){message("Skipping segmentation statistics - segstats set to FALSE")}
      segstats=NULL
    }
    
    if(nearstats){
      near=profoundSegimNear(segim=segim, offset=offset)
    }else{
      near=NULL
    }
    
    if(groupstats){
      group=profoundSegimGroup(segim=segim)
    }else{
      group=NULL
    }
    
    if(haralickstats){
      if(requireNamespace("EBImage", quietly = TRUE)){
        scale=10^(0.4*(30-magzero))
        haralick=as.data.frame(EBImage::computeFeatures.haralick(segim,(image-sky)*scale))
        haralick=haralick[segstats$segID,]
      }else{
        if(verbose){
          message('The EBImage package is needed to compute Haralick statistics.')
          haralick=NULL
        }
      }
    }else{
      haralick=NULL
    }
    
    if(plot){
      if(verbose){message(paste('Plotting segments -',round(proc.time()[3]-timestart,3),'sec'))}
      if(any(is.finite(sky))){
        profoundSegimPlot(image=image-sky, segim=segim, mask=mask, header=header, ...)
      }else{
        profoundSegimPlot(image=image, segim=segim, mask=mask, header=header, ...)
      }
    }else{
      if(verbose){message("Skipping segmentation plot - plot set to FALSE")}
    }
    
    if(!missing(SBlim)){
      SBlimtemp=profoundFlux2SB(flux=skyRMS*skycut, magzero=magzero, pixscale=pixscale)
      SBlim[SBlimtemp>SBlim]=SBlim
      #SBlim=matrix(SBlim,dim(skyRMS)[1],dim(skyRMS)[2])
    }else if(missing(SBlim) & skycut>0){
      SBlim=profoundFlux2SB(flux=skyRMS*skycut, magzero=magzero, pixscale=pixscale)
      #SBlim=matrix(SBlim,dim(skyRMS)[1],dim(skyRMS)[2])
    }else{
      SBlim=NULL
    }
    if(missing(header)){header=NULL}
    if(keepim==FALSE){image=NULL; mask=NULL}
    if(missing(mask)){mask=NULL}
    if(verbose){message(paste('ProFound is finished! -',round(proc.time()[3]-timestart,3),'sec'))}
    output=list(segim=segim, segim_orig=segim_orig, objects=objects, objects_redo=objects_redo, sky=sky, skyRMS=skyRMS, image=image, mask=mask, segstats=segstats, Nseg=dim(segstats)[1], near=near, group=group, haralick=haralick, header=header, SBlim=SBlim, magzero=magzero, dim=dim(segim), pixscale=pixscale, skyarea=skyarea, gain=gain, call=call, date=date(), time=proc.time()[3]-timestart, ProFound.version=packageVersion('ProFound'), R.version=R.version)
  }else{
    if(missing(header)){header=NULL}
    if(keepim==FALSE){image=NULL; mask=NULL}
    if(missing(mask)){mask=NULL}
    if(verbose){message('No objects in segmentation map - skipping dilations and CoG')}
    if(verbose){message(paste('ProFound is finished! -',round(proc.time()[3]-timestart,3),'sec'))}
    output=list(segim=NULL, segim_orig=NULL, objects=NULL, objects_redo=NULL, sky=NULL, skyRMS=NULL, image=image, mask=mask, segstats=NULL, Nseg=0, near=NULL, group=NULL, haralick=NULL, header=header, SBlim=NULL,  magzero=magzero, dim=dim(segim), pixscale=pixscale, skyarea=skyarea, gain=gain, call=call, date=date(), time=proc.time()[3]-timestart, ProFound.version=packageVersion('ProFound'), R.version=R.version)
  }
  class(output)='profound'
  return=output
}

plot.profound=function(x, logR50=TRUE, dmag=0.5, ...){
  
  if(class(x)!='profound'){
    stop('Object class is not of type profound!')
  }
  
  if(is.null(x$image)){
    stop('Missing image!')
  }
  
  if(is.null(x$segim)){
    stop('Missing segmentation map!')
  }
  
  if(is.null(x$sky)){
    x$sky=matrix(0, x$dim[1], x$dim[2])
  }
  if(length(x$sky)==1){
    x$sky=matrix(x$sky, x$dim[1], x$dim[2])
  }
  
  if(is.null(x$skyRMS)){
    x$skyRMS=matrix(1, x$dim[1], x$dim[2])
  }
  if(length(x$skyRMS)==1){
    x$skyRMS=matrix(x$skyRMS, x$dim[1], x$dim[2])
  }
  
  segdiff=x$segim-x$segim_orig
  segdiff[segdiff<0]=0
  
  image=x$image-x$sky
  cmap = rev(colorRampPalette(brewer.pal(9,'RdYlBu'))(100))
  maximg = quantile(abs(image), 0.995, na.rm=TRUE)
  stretchscale = 1/median(abs(image[which(image>0)]), na.rm=TRUE)
  
  layout(matrix(1:9, 3, byrow=TRUE))
  
  if(!is.null(x$header)){
  
    par(mar=c(3.5,3.5,0.5,0.5))
    magimageWCS(image, x$header, stretchscale=stretchscale, locut=-maximg, hicut=maximg, type='num', zlim=c(0,1), col=cmap)
    if(!is.null(x$mask)){magimage(x$mask, locut=0, hicut=1, col=c(NA,hsv(v=0,alpha=0.2)), add=TRUE)}
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimageWCS(x$segim, x$header, col=c(NA, rainbow(max(x$segim,na.rm=TRUE), end=2/3)), magmap=FALSE)
    if(!is.null(x$mask)){magimage(x$mask, locut=0, hicut=1, col=c(NA,hsv(v=0,alpha=0.2)), add=TRUE)}
    abline(v=c(0,dim(x$image)[1]))
    abline(h=c(0,dim(x$image)[2]))
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimageWCS(image/x$skyRMS, x$header)
    magimage(segdiff, col=c(NA, rainbow(max(x$segim,na.rm=TRUE), end=2/3)), magmap=FALSE, add=TRUE)
    if(!is.null(x$mask)){magimage(x$mask, locut=0, hicut=1, col=c(NA,hsv(alpha=0.2)), add=TRUE)}
    
    par(mar=c(3.5,3.5,0.5,0.5))
    if(is.null(x$skyarea)){
      skyarea=prod(x$dim)*x$pixscale^2/(3600^2)
    }else{
      skyarea=x$skyarea
    }
    temphist=maghist(x$segstats$mag, log='y', scale=(2*dmag)/x$skyarea, breaks=seq(floor(min(x$segstats$mag, na.rm = TRUE)), ceiling(max(x$segstats$mag, na.rm = TRUE)),by=0.5), xlab='mag', ylab=paste('#/deg-sq/d',dmag,'mag',sep=''), grid=TRUE)
    #magplot(temphist, log='y', xlab='mag', ylab=expression('#'/'deg-sq'/'dmag'), grid=TRUE)
    ymax=log10(max(temphist$counts,na.rm = T))
    xmax=temphist$mids[which.max(temphist$counts)]
    abline(ymax - xmax*0.6, 0.6, col='red')
    abline(v=xmax+0.25, col='red')
    axis(side=1, at=xmax+0.25, labels=xmax+0.25, tick=FALSE, line=-1, col.axis='red')
      
    par(mar=c(3.5,3.5,0.5,0.5))
    magimageWCS(x$sky, x$header)
    legend('topleft',legend='sky',bg='white')
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimageWCS(x$skyRMS, x$header)
    legend('topleft',legend='skyRMS',bg='white')
    
    maghist(x$segstats$iter, breaks=seq(-0.5,max(x$segstats$iter, na.rm=TRUE)+0.5,by=1), majorn=max(x$segstats$iter, na.rm=TRUE)+1, xlab='Number of Dilations', ylab='#')
    
    par(mar=c(3.5,3.5,0.5,0.5))
    if(logR50){
      magplot(x$segstats$mag, x$segstats$R50, pch='.', col=hsv(alpha=0.5), ylim=c(min(x$segstats$R50, 0.1, na.rm = TRUE), max(x$segstats$R50, 1, na.rm = TRUE)), cex=3, xlab='mag', ylab='R50 / asec', grid=TRUE, log='y')
    }else{
      magplot(x$segstats$mag, x$segstats$R50, pch='.', col=hsv(alpha=0.5), ylim=c(0, max(x$segstats$R50, 1, na.rm = TRUE)), cex=3, xlab='mag', ylab='R50 / asec', grid=TRUE)
    }
    
    par(mar=c(3.5,3.5,0.5,0.5))
    fluxrat=x$segstats$flux/x$segstats$flux_err
    magplot(x$segstats$SB_N90, fluxrat, pch='.', col=hsv(alpha=0.5), ylim=c(0.5,max(fluxrat, 1, na.rm=TRUE)), cex=3, xlab='SB90 / mag/asec-sq', ylab='Flux/Flux-Error', grid=TRUE, log='y')
  
  }else{
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimage(image, stretchscale=stretchscale, locut=-maximg, hicut=maximg, type='num', zlim=c(0,1), col=cmap)
    if(!is.null(x$mask)){magimage(x$mask, locut=0, hicut=1, col=c(NA,hsv(v=0,alpha=0.2)), add=TRUE)}
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimage(x$segim, col=c(NA, rainbow(max(x$segim,na.rm=TRUE), end=2/3)), magmap=FALSE)
    if(!is.null(x$mask)){magimage(x$mask, locut=0, hicut=1, col=c(NA,hsv(v=0,alpha=0.2)), add=TRUE)}
    abline(v=c(0,dim(image)[1]))
    abline(h=c(0,dim(image)[2]))
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimage(image/x$skyRMS)
    magimage(segdiff, col=c(NA, rainbow(max(x$segim,na.rm=TRUE), end=2/3)), magmap=FALSE, add=TRUE)
    if(!is.null(x$mask)){magimage(x$mask, locut=0, hicut=1, col=c(NA,hsv(alpha=0.2)), add=TRUE)}

    par(mar=c(3.5,3.5,0.5,0.5))
    temphist=maghist(x$segstats$mag, log='y', scale=(2*dmag), xlab='mag', ylab=paste('#/d',dmag,'mag',sep=''), grid=TRUE)
    ymax=log10(max(temphist$counts,na.rm = T))
    xmax=temphist$mids[which.max(temphist$counts)]
    abline(ymax - xmax*0.6, 0.6, col='red')
    abline(v=xmax+0.25, col='red')
    axis(side=1, at=xmax+0.25, labels=xmax+0.25, tick=FALSE, line=-1, col.axis='red')
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimage(x$sky)
    legend('topleft',legend='sky',bg='white')
    
    par(mar=c(3.5,3.5,0.5,0.5))
    magimage(x$skyRMS)
    legend('topleft',legend='skyRMS',bg='white')
    
    maghist(x$segstats$iter, breaks=seq(-0.5,max(x$segstats$iter, na.rm=TRUE)+0.5,by=1), majorn=max(x$segstats$iter, na.rm=TRUE)+1, xlab='Number of Dilations', ylab='#')
    
    par(mar=c(3.5,3.5,0.5,0.5))
    if(logR50){
      magplot(x$segstats$mag, x$segstats$R50, pch='.', col=hsv(alpha=0.5), ylim=c(min(x$segstats$R50, 0.1, na.rm = TRUE), max(x$segstats$R50, 1, na.rm = TRUE)), cex=3, xlab='mag', ylab='R50 / asec', grid=TRUE, log='y')
    }else{
      magplot(x$segstats$mag, x$segstats$R50, pch='.', col=hsv(alpha=0.5), ylim=c(0, max(x$segstats$R50, 1, na.rm = TRUE)), cex=3, xlab='mag', ylab='R50 / asec', grid=TRUE)
    }
    
    par(mar=c(3.5,3.5,0.5,0.5))
    fluxrat=x$segstats$flux/x$segstats$flux_err
    magplot(x$segstats$SB_N90, fluxrat, pch='.', col=hsv(alpha=0.5), ylim=c(0.5,max(fluxrat, 1, na.rm=TRUE)), cex=3, xlab='SB90 / mag/pix-sq', ylab='Flux/Flux-Error', grid=TRUE, log='y')
  }
  
}
